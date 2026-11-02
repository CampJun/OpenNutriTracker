import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_nutrition_label_usecase.dart';

class _MemoryStorage implements FlutterSecureStorage {
  final store = <String, String>{'AiTermsAcceptedTag': 'true'};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Secure storage that fails every read, as a corrupted keystore does.
class _BrokenStorage extends _MemoryStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('keystore');
}

class _FakeApi implements NutritionLabelApi {
  final NutritionLabel? label;
  final Object? throws;
  String? sawMediaType;

  _FakeApi({this.label, this.throws});

  @override
  Future<NutritionLabel> read({
    required String mediaType,
    required String base64Data,
  }) async {
    sawMediaType = mediaType;
    if (throws != null) throw throws!;
    return label!;
  }
}

final _photo = MealPhoto(
  bytes: Uint8List.fromList([1, 2, 3]),
  mediaType: 'image/jpeg',
);

ReadNutritionLabelUseCase _subject(
  _FakeApi api, {
  String provider = 'deepseek',
  bool enabled = true,
}) {
  final storage = _MemoryStorage();
  storage.store['AiProviderTag'] = provider;
  storage.store['AiApiKeyTag.$provider'] = 'sk-test';
  storage.store['AiAssistEnabledTag'] = enabled ? 'true' : 'false';
  return ReadNutritionLabelUseCase(
    AiCredentialStorage(storage),
    (selection) => selection.provider == AiProvider.deepseek ? api : null,
  );
}

void main() {
  test('a read label comes back with its failed checks', () async {
    final api = _FakeApi(
      label: const NutritionLabel(
        servingGrams: 56,
        amounts: {LabelNutrient.iron: 1.0},
        dailyValuePercents: {LabelNutrient.iron: 10},
      ),
    );
    final useCase = _subject(api);
    expect(await useCase.isAvailable(), isTrue);

    final result = await useCase.read(_photo);

    expect(api.sawMediaType, 'image/jpeg');
    expect(result, isA<NutritionLabelRead>());
    final read = result as NutritionLabelRead;
    expect(read.flags.single.nutrient, LabelNutrient.iron);
  });

  test('a photo with no nutrition facts is not found, not a failure', () async {
    final result = await _subject(
      _FakeApi(label: const NutritionLabel()),
    ).read(_photo);
    expect(result, isA<NutritionLabelNotFound>());
  });

  test('a provider that cannot read labels is unavailable', () async {
    final useCase = _subject(_FakeApi(), provider: 'anthropic');
    expect(await useCase.isAvailable(), isFalse);
    expect(await useCase.read(_photo), isA<NutritionLabelUnavailable>());
  });

  test('a paused feature is unavailable', () async {
    final useCase = _subject(_FakeApi(), enabled: false);
    expect(await useCase.isAvailable(), isFalse);
  });

  for (final (failure, expected) in [
    (MealInterpreterFailure.auth, MealPhotoFailure.auth),
    (MealInterpreterFailure.billing, MealPhotoFailure.billing),
    (MealInterpreterFailure.rejected, MealPhotoFailure.rejectedImage),
    (MealInterpreterFailure.unsupported, MealPhotoFailure.unsupported),
    (MealInterpreterFailure.timeout, MealPhotoFailure.transient),
  ]) {
    test('${failure.name} is reported as ${expected.name}', () async {
      final result = await _subject(
        _FakeApi(throws: MealInterpreterException('x', failure: failure)),
      ).read(_photo);
      expect((result as NutritionLabelFailed).failure, expected);
    });
  }

  test('a failing credential read is a result, not a throw', () async {
    // The flow holds an undismissable dialog open until read() returns.
    final useCase = ReadNutritionLabelUseCase(
      AiCredentialStorage(_BrokenStorage()),
      (_) => _FakeApi(),
    );
    final result = await useCase.read(_photo);
    expect(result, isA<NutritionLabelFailed>());
  });

  test('an unexpected error is transient', () async {
    final result = await _subject(
      _FakeApi(throws: StateError('bug')),
    ).read(_photo);
    expect(
      (result as NutritionLabelFailed).failure,
      MealPhotoFailure.transient,
    );
  });
}
