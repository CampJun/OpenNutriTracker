import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';

/// What reading a label photo produced.
sealed class NutritionLabelReadResult {
  const NutritionLabelReadResult();
}

/// The model read a label. [flags] are the checks that failed.
final class NutritionLabelRead extends NutritionLabelReadResult {
  final NutritionLabel label;
  final List<LabelFlag> flags;

  const NutritionLabelRead(this.label, this.flags);
}

/// The model answered, but found no nutrition facts in the photo.
final class NutritionLabelNotFound extends NutritionLabelReadResult {
  const NutritionLabelNotFound();
}

/// No provider that can read labels is configured and switched on. The
/// screens only offer label reading when one is, so this is the race where
/// the setting changed while a screen was open.
final class NutritionLabelUnavailable extends NutritionLabelReadResult {
  const NutritionLabelUnavailable();
}

/// The call failed. Worded the same way as a failed meal photo.
final class NutritionLabelFailed extends NutritionLabelReadResult {
  final MealPhotoFailure failure;

  const NutritionLabelFailed(this.failure);
}

/// Reads a nutrition label photo into what it states (docs/adr/0003).
///
/// No fallback: when the model cannot be reached the user types the values,
/// which is always correct.
class ReadNutritionLabelUseCase {
  static final _log = Logger('ReadNutritionLabelUseCase');

  final AiCredentialStorage _credentials;

  /// Null for a provider that cannot read labels. Read per call, like the
  /// meal photo path, so a credential is never captured for the lifetime
  /// of a singleton.
  final NutritionLabelApi? Function(AiSelection selection) _apiFactory;

  ReadNutritionLabelUseCase(this._credentials, this._apiFactory);

  /// Whether label reading can be offered right now.
  Future<bool> isAvailable() async {
    final selection = await _credentials.readSelection();
    return selection != null && _apiFactory(selection) != null;
  }

  Future<NutritionLabelReadResult> read(MealPhoto photo) async {
    final selection = await _credentials.readSelection();
    final api = selection == null ? null : _apiFactory(selection);
    if (api == null) return const NutritionLabelUnavailable();

    try {
      final label = await api.read(
        mediaType: photo.mediaType,
        base64Data: base64Encode(photo.bytes),
      );
      if (label.isEmpty) return const NutritionLabelNotFound();
      return NutritionLabelRead(label, checkNutritionLabel(label));
    } on MealInterpreterException catch (e) {
      _log.info('Label read failed: ${e.reason}');
      return NutritionLabelFailed(switch (e.failure) {
        MealInterpreterFailure.auth => MealPhotoFailure.auth,
        MealInterpreterFailure.rejected => MealPhotoFailure.rejectedImage,
        MealInterpreterFailure.unsupported => MealPhotoFailure.unsupported,
        MealInterpreterFailure.billing => MealPhotoFailure.billing,
        MealInterpreterFailure.insecureDestination =>
          MealPhotoFailure.insecureDestination,
        MealInterpreterFailure.timeout ||
        MealInterpreterFailure.transient => MealPhotoFailure.transient,
      });
    } catch (e, stackTrace) {
      _log.severe('Label read failed unexpectedly', e, stackTrace);
      return const NutritionLabelFailed(MealPhotoFailure.transient);
    }
  }
}
