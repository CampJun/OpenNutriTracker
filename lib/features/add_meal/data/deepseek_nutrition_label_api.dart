import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_interpreter_exception.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';

/// Reads a nutrition label photo with DeepSeek, over its chat-completions
/// API (docs/adr/0003).
///
/// A forced tool call with thinking off, the configuration measured on the
/// prototype's seven labels: 99% of fields, identical across runs, about two
/// seconds a call. Thinking on was no more accurate, slower, and refuses a
/// forced tool call outright.
class DeepSeekNutritionLabelApi implements NutritionLabelApi {
  static final _log = Logger('DeepSeekNutritionLabelApi');

  /// A label's JSON is about 300 tokens; the cap only bounds a runaway.
  static const _maxTokens = 2048;

  static const defaultTimeout = Duration(seconds: 30);

  final http.Client _client;
  final String Function() _apiKey;
  final String model;
  final Duration timeout;

  DeepSeekNutritionLabelApi(
    this._client,
    this._apiKey, {
    required this.model,
    this.timeout = defaultTimeout,
  });

  @override
  Future<NutritionLabel> read({
    required String mediaType,
    required String base64Data,
  }) async {
    final body = jsonEncode({
      ...OpenAiCompatibleMealItemsApi.deepSeekThinkingOff,
      'model': model,
      'max_tokens': _maxTokens,
      'temperature': 0,
      'messages': [
        {'role': 'system', 'content': nutritionLabelSystemPrompt},
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mediaType;base64,$base64Data'},
            },
            {'type': 'text', 'text': nutritionLabelPhotoPrompt},
          ],
        },
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': nutritionLabelToolName,
            'description': nutritionLabelToolDescription,
            'parameters': nutritionLabelToolSchema,
          },
        },
      ],
      'tool_choice': {
        'type': 'function',
        'function': {'name': nutritionLabelToolName},
      },
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            OpenAiCompatibleMealItemsApi.deepSeekEndpoint,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${_apiKey()}',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      _log.info('Label read exceeded ${timeout.inSeconds}s');
      throw const MealInterpreterException('request timed out');
    } catch (_) {
      // Not logging the error: it can carry part of the payload, which is
      // the photograph.
      throw const MealInterpreterException('request failed');
    }

    if (response.statusCode != 200) {
      _log.warning('Label read failed with ${response.statusCode}');
      throw MealInterpreterException(
        'provider returned ${response.statusCode}',
        failure: OpenAiCompatibleMealItemsApi.deepSeekFailureFor(
          response.statusCode,
        ),
        statusCode: response.statusCode,
      );
    }

    return nutritionLabelFromJson(_arguments(response.body));
  }

  /// The forced tool call's arguments, decoded. Every other shape raises.
  Object? _arguments(String responseBody) {
    final Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } catch (_) {
      throw const MealInterpreterException('malformed response');
    }
    final choices = decoded is Map ? decoded['choices'] : null;
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = choice is Map ? choice['message'] : null;
    final calls = message is Map ? message['tool_calls'] : null;
    if (calls is List) {
      for (final call in calls) {
        final function = call is Map ? call['function'] : null;
        if (function is! Map || function['name'] != nutritionLabelToolName) {
          continue;
        }
        final arguments = function['arguments'];
        if (arguments is Map) return arguments;
        if (arguments is String) {
          try {
            return jsonDecode(arguments);
          } catch (_) {
            throw const MealInterpreterException('malformed tool arguments');
          }
        }
      }
    }
    throw const MealInterpreterException(
      'response has no tool call',
      failure: MealInterpreterFailure.unsupported,
    );
  }
}
