import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/data/deepseek_nutrition_label_api.dart';
import 'package:opennutritracker/features/add_meal/data/meal_items_api_factory.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';

http.Response _toolCall(Object arguments) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': 'tool_calls',
        'message': {
          'tool_calls': [
            {
              'type': 'function',
              'function': {
                'name': nutritionLabelToolName,
                'arguments': arguments is String
                    ? arguments
                    : jsonEncode(arguments),
              },
            },
          ],
        },
      },
    ],
  }),
  200,
);

void main() {
  test('sends the photo as a forced tool call with thinking off', () async {
    late http.Request sent;
    final api = DeepSeekNutritionLabelApi(
      MockClient((request) async {
        sent = request;
        return _toolCall({'servingGrams': 31, 'energyKcal': 160});
      }),
      () => 'sk-test',
      model: 'deepseek-flash',
    );

    final label = await api.read(mediaType: 'image/jpeg', base64Data: 'QUJD');

    expect(sent.url, OpenAiCompatibleMealItemsApi.deepSeekEndpoint);
    expect(sent.headers['authorization'], 'Bearer sk-test');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-flash');
    // DeepSeek refuses a forced tool call while thinking is on.
    expect(body['thinking'], {'type': 'disabled'});
    expect(body['tool_choice'], {
      'type': 'function',
      'function': {'name': nutritionLabelToolName},
    });
    final content = (body['messages'] as List).last['content'] as List<dynamic>;
    expect(content.first['image_url']['url'], 'data:image/jpeg;base64,QUJD');
    expect(label.servingGrams, 31);
    expect(label.amounts[LabelNutrient.energyKcal], 160);
  });

  for (final (status, failure) in [
    (401, MealInterpreterFailure.auth),
    (402, MealInterpreterFailure.billing),
    (400, MealInterpreterFailure.rejected),
    (422, MealInterpreterFailure.rejected),
    (503, MealInterpreterFailure.transient),
  ]) {
    test('status $status is ${failure.name}', () {
      final api = DeepSeekNutritionLabelApi(
        MockClient((_) async => http.Response('{}', status)),
        () => 'k',
        model: 'deepseek-flash',
      );
      expect(
        api.read(mediaType: 'image/jpeg', base64Data: ''),
        throwsA(
          isA<MealInterpreterException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
    });
  }

  test('a reply with no tool call is a capability failure', () {
    final api = DeepSeekNutritionLabelApi(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Calories 160'},
              },
            ],
          }),
          200,
        ),
      ),
      () => 'k',
      model: 'deepseek-flash',
    );
    expect(
      api.read(mediaType: 'image/jpeg', base64Data: ''),
      throwsA(
        isA<MealInterpreterException>().having(
          (e) => e.failure,
          'failure',
          MealInterpreterFailure.unsupported,
        ),
      ),
    );
  });

  test('only DeepSeek reads labels', () {
    final client = MockClient((_) async => http.Response('{}', 200));
    for (final provider in AiProvider.values) {
      final api = nutritionLabelApiFor(
        client,
        AiSelection(provider: provider, apiKey: 'k'),
      );
      expect(api != null, provider == AiProvider.deepseek, reason: '$provider');
    }
  });

  test('DeepSeek meal logging turns thinking off too', () async {
    late Map<String, dynamic> body;
    final api = mealItemsApiFor(
      MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'name': 'log_meal_items',
                        'arguments': '{"items": []}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
      const AiSelection(provider: AiProvider.deepseek, apiKey: 'k'),
    );
    await api.requestItems(
      content: const MealTextContent('2 eggs'),
      system: 'system',
    );
    expect(body['thinking'], {'type': 'disabled'});
    expect(body['model'], 'deepseek-flash');
    expect(body['tool_choice'], isA<Map>());
  });
}
