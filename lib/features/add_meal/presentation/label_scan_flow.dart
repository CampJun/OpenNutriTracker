import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_meal_photo_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/read_nutrition_label_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

final _log = Logger('LabelScanFlow');

/// Where a Custom Food created from a label goes once reviewed.
class LabelScanTarget {
  final DateTime day;
  final IntakeTypeEntity intakeType;
  final bool usesImperialUnits;
  final LogTray? logTray;

  /// A barcode the new Custom Food carries, so the next scan finds it.
  final String? barcode;

  const LabelScanTarget({
    required this.day,
    required this.intakeType,
    required this.usesImperialUnits,
    this.logTray,
    this.barcode,
  });
}

/// Photographs a nutrition label and opens the reviewed Custom Food
/// (docs/adr/0003). Every way out of it either opens the review screen or
/// offers to enter the values by hand, keeping [LabelScanTarget.barcode].
///
/// [replace] swaps the current route for the review screen: the scanner
/// uses it so Back from the review does not land on a dead "not found".
Future<void> startLabelScan(
  BuildContext context,
  LabelScanTarget target, {
  bool replace = false,
}) async {
  final s = S.of(context);
  final proceed = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${s.labelScanDisclosure}\n\n${s.aiAssistExperimentalNote}',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ),
          Semantics(
            identifier: 'label-scan-camera',
            child: ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(s.labelScanTakePhotoLabel),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ),
        ],
      ),
    ),
  );
  if (proceed != true || !context.mounted) return;

  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(source: ImageSource.camera);
  } catch (e, stackTrace) {
    _log.warning('Opening the label camera failed', e, stackTrace);
    if (!context.mounted) return;
    return _offerFallback(
      context,
      target,
      s.bulkAddPhotoCameraFailedLabel,
      replace: replace,
    );
  }
  // A cancelled camera is not a failure and says nothing.
  if (picked == null || !context.mounted) return;

  MealPhoto? photo;
  try {
    // Discards the camera's copy once encoded: no photo is kept.
    photo = await MealPhotoEncoder.encodeAndDiscardSource(
      picked.path,
      format: MealPhotoFormat.forProvider(AiProvider.deepseek),
    );
  } catch (e, stackTrace) {
    _log.warning('Encoding a label photo failed', e, stackTrace);
  }
  if (!context.mounted) return;
  if (photo == null) {
    return _offerFallback(
      context,
      target,
      s.bulkAddPhotoUnreadableLabel,
      replace: replace,
    );
  }

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text(s.labelScanReadingLabel)),
          ],
        ),
      ),
    ),
  );
  final result = await locator<ReadNutritionLabelUseCase>().read(photo);
  navigator.pop(); // the reading dialog
  if (!context.mounted) return;

  switch (result) {
    case NutritionLabelRead(:final label, :final flags):
      _openReview(
        context,
        target,
        customFoodFromLabel(label, barcode: target.barcode),
        review: LabelReview(label, flags),
        replace: replace,
      );
    case NutritionLabelNotFound():
      _offerFallback(
        context,
        target,
        s.labelScanNotFoundLabel,
        replace: replace,
      );
    case NutritionLabelUnavailable():
      _offerFallback(
        context,
        target,
        s.bulkAddPhotoUnavailableLabel,
        replace: replace,
      );
    case NutritionLabelFailed(:final failure):
      _offerFallback(context, target, switch (failure) {
        MealPhotoFailure.auth => s.bulkAddPhotoKeyRejectedLabel,
        MealPhotoFailure.billing => s.labelScanNoCreditLabel,
        MealPhotoFailure.rejectedImage => s.bulkAddPhotoUnreadableLabel,
        MealPhotoFailure.unsupported => s.labelScanUnsupportedLabel,
        MealPhotoFailure.insecureDestination =>
          s.bulkAddModelInsecureServerLabel,
        MealPhotoFailure.transient => s.bulkAddPhotoFailedLabel,
      }, replace: replace);
  }
}

/// Says what went wrong and offers the two ways on: try again, or type the
/// values from the label. Both keep the barcode.
Future<void> _offerFallback(
  BuildContext context,
  LabelScanTarget target,
  String message, {
  required bool replace,
}) async {
  final s = S.of(context);
  final choice = await showDialog<_FallbackChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(s.dialogCancelLabel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_FallbackChoice.manual),
          child: Text(s.labelScanEnterManuallyLabel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_FallbackChoice.retry),
          child: Text(s.retryLabel),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _FallbackChoice.retry:
      await startLabelScan(context, target, replace: replace);
    case _FallbackChoice.manual:
      openNewCustomFood(context, target, replace: replace);
    case null:
      break;
  }
}

enum _FallbackChoice { retry, manual }

/// The custom-food form, empty but for [LabelScanTarget.barcode].
void openNewCustomFood(
  BuildContext context,
  LabelScanTarget target, {
  bool replace = false,
}) {
  _openReview(
    context,
    target,
    customFoodFromLabel(const NutritionLabel(), barcode: target.barcode),
    replace: replace,
  );
}

void _openReview(
  BuildContext context,
  LabelScanTarget target,
  MealEntity meal, {
  LabelReview? review,
  required bool replace,
}) {
  final arguments = EditMealScreenArguments(
    target.day,
    meal,
    target.intakeType,
    target.usesImperialUnits,
    logTray: target.logTray,
    labelReview: review,
  );
  final navigator = Navigator.of(context);
  if (replace) {
    navigator.pushReplacementNamed(
      NavigationOptions.editMealRoute,
      arguments: arguments,
    );
  } else {
    navigator.pushNamed(NavigationOptions.editMealRoute, arguments: arguments);
  }
}
