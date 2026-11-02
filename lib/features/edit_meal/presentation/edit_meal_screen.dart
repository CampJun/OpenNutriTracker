import 'dart:async';
import 'dart:math' as math;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image_picker_tile.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/barcode_validator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/food_name_validator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/presentation/log_tray.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/widgets/default_meal_image.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class EditMealScreen extends StatefulWidget {
  const EditMealScreen({super.key});

  @override
  State<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends State<EditMealScreen> {
  final log = Logger('EditMealScreen');
  late MealEntity _mealEntity;
  late DateTime _day;
  late IntakeTypeEntity _intakeTypeEntity;
  late bool _usesImperialUnits;
  LogTray? _logTray;

  late bool _editOnly;

  late EditMealBloc _editMealBloc;

  /// Tracks the active form view (#232). Hydrated from ConfigDBO once the
  /// bloc finishes loading, and persisted back whenever the user toggles.
  CustomMealFormMode _formMode = CustomMealFormMode.simple;
  bool _formModeHydrated = false;

  final _nameTextController = TextEditingController();
  final _brandsTextController = TextEditingController();
  final _barcodeTextController = TextEditingController();
  final _mealQuantityTextController = TextEditingController();
  final _servingQuantityTextController = TextEditingController();
  final _baseQuantityTextController = TextEditingController();
  final _kcalTextController = TextEditingController();
  final _carbsTextController = TextEditingController();
  final _fatTextController = TextEditingController();
  final _proteinTextController = TextEditingController();
  // Advanced-mode micronutrient controllers (#232 follow-up: all 10 panel nutrients)
  final _fiberTextController = TextEditingController();
  final _saturatedFatTextController = TextEditingController();
  final _sugarsTextController = TextEditingController();
  final _sodiumTextController = TextEditingController();
  final _calciumTextController = TextEditingController();
  final _ironTextController = TextEditingController();
  final _potassiumTextController = TextEditingController();
  final _magnesiumTextController = TextEditingController();
  final _vitaminDTextController = TextEditingController();
  final _vitaminB12TextController = TextEditingController();
  // The other ten nutrients the app stores. Shown in Advanced mode since
  // label reading, which fills them (docs/adr/0003).
  final _transFatTextController = TextEditingController();
  final _cholesterolTextController = TextEditingController();
  final _monounsaturatedFatTextController = TextEditingController();
  final _polyunsaturatedFatTextController = TextEditingController();
  final _vitaminATextController = TextEditingController();
  final _vitaminCTextController = TextEditingController();
  final _vitaminB6TextController = TextEditingController();
  final _niacinTextController = TextEditingController();
  final _zincTextController = TextEditingController();
  final _phosphorusTextController = TextEditingController();

  /// Non-null while reviewing a label read.
  LabelReview? _labelReview;

  /// The label checks run against what the fields hold now, so a value the
  /// user corrects stops being flagged. Recomputed on every build.
  List<LabelFlag> _labelFlags = const [];

  /// The field each label nutrient is reviewed in. Energy is absent: its
  /// field shows the user's energy unit and is filled separately.
  late final Map<LabelNutrient, TextEditingController> _labelFields = {
    LabelNutrient.fat: _fatTextController,
    LabelNutrient.saturatedFat: _saturatedFatTextController,
    LabelNutrient.transFat: _transFatTextController,
    LabelNutrient.monounsaturatedFat: _monounsaturatedFatTextController,
    LabelNutrient.polyunsaturatedFat: _polyunsaturatedFatTextController,
    LabelNutrient.cholesterol: _cholesterolTextController,
    LabelNutrient.sodium: _sodiumTextController,
    LabelNutrient.carbohydrates: _carbsTextController,
    LabelNutrient.fiber: _fiberTextController,
    LabelNutrient.sugars: _sugarsTextController,
    LabelNutrient.protein: _proteinTextController,
    LabelNutrient.vitaminA: _vitaminATextController,
    LabelNutrient.vitaminC: _vitaminCTextController,
    LabelNutrient.vitaminD: _vitaminDTextController,
    LabelNutrient.vitaminB6: _vitaminB6TextController,
    LabelNutrient.vitaminB12: _vitaminB12TextController,
    LabelNutrient.niacin: _niacinTextController,
    LabelNutrient.calcium: _calciumTextController,
    LabelNutrient.iron: _ironTextController,
    LabelNutrient.magnesium: _magnesiumTextController,
    LabelNutrient.zinc: _zincTextController,
    LabelNutrient.phosphorus: _phosphorusTextController,
    LabelNutrient.potassium: _potassiumTextController,
  };

  final _units = ['g', 'ml', 'g/ml'];
  String? selectedUnit;
  bool _isTotal = false;
  // Default on so behaviour matches what existing users are used to — the
  // meal is saved to their custom list unless they actively untick the box.
  // #249 adds the *option* to skip the save; it does not change the default.
  bool _saveForLater = true;

  late List<ButtonSegment<String>> _mealUnitButtonSegment;

  // didChangeDependencies is called on every dependency change, including
  // ones triggered by Navigator pops returning from sub-pages (the barcode
  // scanner among them). Without this guard the controllers would get
  // re-seeded from _mealEntity.code on every return, wiping a value the
  // user just scanned into the field.
  bool _initialised = false;

  String baseQuantity = "100";

  /// Tracks the unit the energy field was last rendered in, so that when
  /// the user flips between kcal and kJ in Settings mid-edit we can
  /// re-display the same underlying energy in the new unit. `null` until
  /// the first build seeds the field.
  bool? _lastRenderedUsesKj;

  // #64 follow-up: user-attached photo for a custom meal. Mirrors
  // _mealEntity.localImagePath but is held separately so the picker
  // can update the on-screen preview before the parent entity is
  // rebuilt at save time.
  String? _localImagePath;
  bool _localImageCleared = false;

  @override
  void initState() {
    super.initState();
    // Initialize once, not during build.
    _editMealBloc = locator<EditMealBloc>();
    _editMealBloc.add(InitializeEditMealEvent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as EditMealScreenArguments;
    _mealEntity = args.mealEntity;
    _day = args.day;
    _intakeTypeEntity = args.intakeTypeEntity;
    _usesImperialUnits = args.usesImperialUnits;
    _editOnly = args.editOnly;
    _logTray = args.logTray;

    _nameTextController.text = _mealEntity.name ?? "";
    _brandsTextController.text = _mealEntity.brands ?? "";
    // MealEntity.code is dual-purpose: it carries a real product barcode for
    // OFF / FDC scans, but for custom meals MealEntity.empty() seeds it with
    // an internal UUID that the user should never see in the Barcode input.
    // Only show codes that actually look like a retail barcode (8–14 digits);
    // anything else means there isn't a user-visible barcode yet.
    final existingCode = _mealEntity.code;
    _barcodeTextController.text =
        (existingCode != null && isBarcodeFormatValid(existingCode))
            ? existingCode
            : "";
    _mealQuantityTextController.text =
        _mealEntity.mealQuantity?.withDotDecimal() ?? "";
    _servingQuantityTextController.text =
        _mealEntity.servingQuantity.toStringOrEmpty();
    // Seed the energy field in the user's currently-selected unit (#177
    // follow-up). Storage stays kcal — we only translate at the edges.
    final usesKjOnLoad =
        Provider.of<EnergyUnitProvider>(context, listen: false).usesKilojoules;
    _kcalTextController.text = _formatStoredKcalForDisplay(
      _mealEntity.nutriments.energyKcal100,
      usesKjOnLoad,
    );
    _lastRenderedUsesKj = usesKjOnLoad;
    _carbsTextController.text =
        _mealEntity.nutriments.carbohydrates100.toStringOrEmpty();
    _fatTextController.text = _mealEntity.nutriments.fat100.toStringOrEmpty();
    _proteinTextController.text =
        _mealEntity.nutriments.proteins100.toStringOrEmpty();
    _fiberTextController.text =
        _mealEntity.nutriments.fiber100.toStringOrEmpty();
    _saturatedFatTextController.text =
        _mealEntity.nutriments.saturatedFat100.toStringOrEmpty();
    _sugarsTextController.text =
        _mealEntity.nutriments.sugars100.toStringOrEmpty();
    _sodiumTextController.text =
        _mealEntity.nutriments.sodium100.toStringOrEmpty();
    _calciumTextController.text =
        _mealEntity.nutriments.calcium100.toStringOrEmpty();
    _ironTextController.text =
        _mealEntity.nutriments.iron100.toStringOrEmpty();
    _potassiumTextController.text =
        _mealEntity.nutriments.potassium100.toStringOrEmpty();
    _magnesiumTextController.text =
        _mealEntity.nutriments.magnesium100.toStringOrEmpty();
    _vitaminDTextController.text =
        _mealEntity.nutriments.vitaminD100.toStringOrEmpty();
    _vitaminB12TextController.text =
        _mealEntity.nutriments.vitaminB12100.toStringOrEmpty();
    final n = _mealEntity.nutriments;
    _transFatTextController.text = n.transFat100.toStringOrEmpty();
    _cholesterolTextController.text = n.cholesterol100.toStringOrEmpty();
    _monounsaturatedFatTextController.text =
        n.monounsaturatedFat100.toStringOrEmpty();
    _polyunsaturatedFatTextController.text =
        n.polyunsaturatedFat100.toStringOrEmpty();
    _vitaminATextController.text = n.vitaminA100.toStringOrEmpty();
    _vitaminCTextController.text = n.vitaminC100.toStringOrEmpty();
    _vitaminB6TextController.text = n.vitaminB6100.toStringOrEmpty();
    _niacinTextController.text = n.niacin100.toStringOrEmpty();
    _zincTextController.text = n.zinc100.toStringOrEmpty();
    _phosphorusTextController.text = n.phosphorus100.toStringOrEmpty();
    _localImagePath = _mealEntity.localImagePath;
    selectedUnit = _switchButtonUnit(_mealEntity.mealUnit);

    // Convert meal size to imperial units if necessary
    if (_usesImperialUnits) {
      _mealQuantityTextController.text = _convertToImperial(
        _mealQuantityTextController.text,
        _mealEntity.mealUnit ?? "0",
      );
      _servingQuantityTextController.text = _convertToImperial(
        _servingQuantityTextController.text,
        _mealEntity.mealUnit ?? "0",
      );
    }

    _labelReview = args.labelReview;
    if (_labelReview != null) _seedFromLabel(_labelReview!, usesKjOnLoad);

    _mealUnitButtonSegment = [
      ButtonSegment(
        value: _units[0],
        label: Text(
          _usesImperialUnits ? S.of(context).ozUnit : S.of(context).gramUnit,
        ),
      ),
      ButtonSegment(
        value: _units[1],
        label: Text(
          _usesImperialUnits
              ? S.of(context).flOzUnit
              : S.of(context).milliliterUnit,
        ),
      ),
      ButtonSegment(
        value: _units[2],
        label: Text(S.of(context).gramMilliliterUnit),
      ),
    ];
  }

  /// Opens the form on the label's own numbers: Advanced mode, grams, and a
  /// base quantity of one Label Serving, so every field reads exactly as
  /// the label prints it. Saving scales them to per 100 g as usual.
  void _seedFromLabel(LabelReview review, bool usesKj) {
    final label = review.label;
    _formMode = CustomMealFormMode.advanced;
    // The stored preference must not switch a review to Simple mode, which
    // would save none of the micronutrients.
    _formModeHydrated = true;
    _isTotal = false;
    selectedUnit = _units[0];
    // Grams, whatever the unit setting: the save reads the base quantity
    // as grams.
    _baseQuantityTextController.text = _labelAmountText(label.servingGrams);
    _kcalTextController.text = _formatStoredKcalForDisplay(
      label.amounts[LabelNutrient.energyKcal],
      usesKj,
    );
    for (final entry in _labelFields.entries) {
      entry.value.text = _labelAmountText(label.amounts[entry.key]);
    }
    for (final controller in [
      _baseQuantityTextController,
      _kcalTextController,
      ..._labelFields.values,
    ]) {
      controller.addListener(_onLabelFieldChanged);
    }
  }

  /// Rebuilds so the flags follow an edit. A change made during a build
  /// (the energy field re-rendered in a new unit) is already being drawn.
  void _onLabelFieldChanged() {
    if (!mounted ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      return;
    }
    setState(() {});
  }

  /// [checkNutritionLabel] over the fields' current values, read as one
  /// Label Serving of the base quantity's weight. Totals mode shows no
  /// flags: its values are not per serving, so the checks do not apply.
  List<LabelFlag> _checkLabelFields(LabelReview review) {
    if (_isTotal) return const [];
    double? parse(TextEditingController c) => double.tryParse(c.text.trim());
    final energy = parse(_kcalTextController);
    final kcal = (energy != null && (_lastRenderedUsesKj ?? false))
        ? UnitCalc.kjToKcal(energy)
        : energy;
    final grams = parse(_baseQuantityTextController);
    return checkNutritionLabel(
      NutritionLabel(
        servingGrams: (grams != null && grams > 0) ? grams : null,
        amounts: {
          for (final entry in _labelFields.entries)
            entry.key: ?parse(entry.value),
          LabelNutrient.energyKcal: ?kcal,
          // No field: the label's own reading stands.
          LabelNutrient.addedSugars:
              ?review.label.amounts[LabelNutrient.addedSugars],
        },
        dailyValuePercents: review.label.dailyValuePercents,
      ),
    );
  }

  /// A label amount the way the label prints it: "14", not "14.0".
  static String _labelAmountText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  /// Why [nutrient]'s field is highlighted, or null. Null [nutrient] asks
  /// about the serving weight.
  String? _labelFlagText(LabelNutrient? nutrient) {
    if (_labelReview == null) return null;
    final s = S.of(context);
    final texts = [
      for (final flag in _labelFlags)
        if (flag.nutrient == nutrient)
          switch (flag.kind) {
            LabelFlagKind.dailyValueMismatch => s.labelFlagDailyValue(
              _formatLabelNumber(flag.printedPercent!),
              _formatLabelNumber(flag.impliedAmount!),
              _labelUnitText(flag.nutrient!.unit),
            ),
            LabelFlagKind.energyMismatch => s.labelFlagEnergy(
              flag.computedKcal!.round().toString(),
            ),
            LabelFlagKind.partExceedsTotal => s.labelFlagPartExceedsTotal(
              _labelNutrientName(flag.part!),
              _formatLabelNumber(flag.partAmount!),
            ),
            LabelFlagKind.macrosExceedServing =>
              s.labelFlagMacrosExceedServing,
            LabelFlagKind.servingWeightMissing =>
              s.labelFlagServingWeightMissing,
          },
    ];
    return texts.isEmpty ? null : texts.join('\n');
  }

  String _labelNutrientName(LabelNutrient nutrient) {
    final s = S.of(context);
    return switch (nutrient) {
      LabelNutrient.saturatedFat => s.saturatedFatLabel,
      LabelNutrient.transFat => s.transFatLabel,
      LabelNutrient.addedSugars => s.labelAddedSugarsLabel,
      LabelNutrient.fiber => s.fiberLabel,
      LabelNutrient.sugars => s.sugarLabel,
      _ => nutrient.name,
    };
  }

  static String _labelUnitText(LabelUnit unit) => switch (unit) {
    LabelUnit.g => 'g',
    LabelUnit.mg => 'mg',
    LabelUnit.mcg => 'µg',
    LabelUnit.kcal => 'kcal',
  };

  static String _formatLabelNumber(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  @override
  void dispose() {
    _nameTextController.dispose();
    _brandsTextController.dispose();
    _barcodeTextController.dispose();
    _mealQuantityTextController.dispose();
    _servingQuantityTextController.dispose();
    _baseQuantityTextController.dispose();
    _kcalTextController.dispose();
    _carbsTextController.dispose();
    _fatTextController.dispose();
    _proteinTextController.dispose();
    for (final controller in [
      _fiberTextController,
      _saturatedFatTextController,
      _sugarsTextController,
      _sodiumTextController,
      _calciumTextController,
      _ironTextController,
      _potassiumTextController,
      _magnesiumTextController,
      _vitaminDTextController,
      _vitaminB12TextController,
      _transFatTextController,
      _cholesterolTextController,
      _monounsaturatedFatTextController,
      _polyunsaturatedFatTextController,
      _vitaminATextController,
      _vitaminCTextController,
      _vitaminB6TextController,
      _niacinTextController,
      _zincTextController,
      _phosphorusTextController,
    ]) {
      controller.dispose();
    }
    // Do not close _editMealBloc here if provided as a singleton by locator.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the energy-unit provider so the form reacts when the user
    // flips between kcal and kJ in Settings while this screen is open.
    final usesKj = context.watch<EnergyUnitProvider>().usesKilojoules;
    _maybeReinterpretKcalField(usesKj);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return SafeArea(
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
          title: Text(
            S.of(context).editMealLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Dimens.spacing16, 0, Dimens.spacing16, 0),
              child: Semantics(
                identifier: 'edit-meal-save',
                child: FilledButton(
                  onPressed: () => _onSavePressed(_usesImperialUnits),
                  style: FilledButton.styleFrom(
                    shape: const RoundedRectangleBorder(borderRadius: Dimens.borderRadiusM),
                  ),
                  child: Text(S.of(context).buttonSaveLabel),
                ),
              ),
            ),
          ],
        ),
        body: BlocBuilder<EditMealBloc, EditMealState>(
          bloc: _editMealBloc,
          builder: (BuildContext context, EditMealState state) {
            if (state is EditMealLoadingState) {
              return _getLoadingContent();
            } else if (state is EditMealLoadedState) {
              if (!_formModeHydrated) {
                _formMode = state.formMode;
                _formModeHydrated = true;
              }
              return _getLoadedContent(state.usesImperialUnits, usesKj);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  /// Re-interpret whatever the user has typed in the energy field when
  /// the active energy unit changes mid-edit. The current text is
  /// interpreted as the previously-rendered unit, converted to the new
  /// unit, and written back so the displayed quantity matches the new
  /// unit suffix. We round to one decimal place to keep the field tidy.
  void _maybeReinterpretKcalField(bool usesKj) {
    if (_lastRenderedUsesKj == null || _lastRenderedUsesKj == usesKj) {
      _lastRenderedUsesKj = usesKj;
      return;
    }
    final current = double.tryParse(_kcalTextController.text);
    if (current != null) {
      final converted = usesKj
          ? UnitCalc.kcalToKj(current)
          : UnitCalc.kjToKcal(current);
      _kcalTextController.text =
          double.parse(converted.toStringAsFixed(1)).toStringOrEmpty();
    }
    _lastRenderedUsesKj = usesKj;
  }

  /// Convert a stored kcal value into the string the user should see in
  /// the energy field, given the active unit. One decimal place is
  /// plenty for an input field; saving rounds back to kcal anyway.
  String _formatStoredKcalForDisplay(double? storedKcal, bool usesKj) {
    if (storedKcal == null) return "";
    final display = usesKj ? UnitCalc.kcalToKj(storedKcal) : storedKcal;
    return double.parse(display.toStringAsFixed(1)).toStringOrEmpty();
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _getLoadedContent(bool usesImperialUnits, bool usesKj) {
    final review = _labelReview;
    if (review != null) _labelFlags = _checkLabelFields(review);
    final isSimple = _formMode == CustomMealFormMode.simple;
    final energyUnitSuffix =
        usesKj ? S.of(context).kjLabel : S.of(context).kcalLabel;
    // The mass unit every Advanced field is read in, following the unit
    // selector (now the first Advanced field) so the labels and the per-100
    // helper all track the user's choice (#495).
    final unitSuffix = _massUnitSuffix(context);
    // A label review seeds the base quantity in grams whatever the unit
    // setting, and the save reads it as grams, so it is labelled grams.
    final baseUnitSuffix =
        _labelReview != null ? S.of(context).gramUnit : unitSuffix;
    final String advancedHelper = _isTotal
        ? S.of(context).mealNutrientsTotalLabel
        : S.of(context).mealNutrientsPerQtyLabel(_getDisplayQuantity(), baseUnitSuffix);
    final String energyHelper = isSimple
        ? S.of(context).customMealFormSimpleFieldHelper(energyUnitSuffix)
        : advancedHelper;
    final String macroHelper = isSimple
        ? S.of(context).customMealFormSimpleFieldHelper('g')
        : advancedHelper;
    // perQtyHelper is the advanced-mode helper, passed to the micronutrient fields.
    final String? perQtyHelper = isSimple ? null : advancedHelper;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_labelReview != null) ...[
          _LabelReviewBanner(flagged: _labelFlags.isNotEmpty),
          const SizedBox(height: 16),
        ],
        // Custom meals get the same picker tile recipes use — a single
        // tappable circle with an overlay camera icon, "Add a photo"
        // text beneath, and a bottom-sheet for the action choice.
        // OFF / FDC entries keep the existing remote-image avatar:
        // they cannot have a user-attached photo, so showing the
        // picker affordance would be misleading.
        if (_mealEntity.source == MealSourceEntity.custom)
          Center(
            child: UserImagePickerTile(
              kind: UserImageKind.meal,
              imagePath: _localImagePath,
              onPickFromGallery: () => _onPickMealImage(ImageSource.gallery),
              onTakePhoto: () => _onPickMealImage(ImageSource.camera),
              onRemove: _onRemoveMealImage,
            ),
          )
        else
          Center(child: _buildRemoteMealImage()),
        const SizedBox(height: 24),
        // Simple / Advanced toggle (#232). The reporter wanted to log a
        // homemade meal as "name + per-serving macros" without the per-100g
        // scaffolding; the advanced view keeps the precise path for users
        // who care about base quantities and serving math.
        // Hidden while reviewing a label: Simple mode keeps no
        // micronutrients and no serving, so it would lose most of the read.
        if (_mealEntity.source == MealSourceEntity.custom &&
            _labelReview == null) ...[
          Text(
            S.of(context).customMealFormModeLabel,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'edit-meal-mode-toggle',
            child: SegmentedButton<CustomMealFormMode>(
              segments: [
                ButtonSegment(
                  value: CustomMealFormMode.simple,
                  label: Text(S.of(context).customMealFormSimple),
                ),
                ButtonSegment(
                  value: CustomMealFormMode.advanced,
                  label: Text(S.of(context).customMealFormAdvanced),
                ),
              ],
              selected: {_formMode},
              onSelectionChanged: (Set<CustomMealFormMode> selection) {
                final newMode = selection.first;
                setState(() {
                  _formMode = newMode;
                });
                _editMealBloc.setFormMode(newMode);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSimple
                ? S.of(context).customMealFormSimpleHelp
                : S.of(context).customMealFormAdvancedHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: _nameTextController,
          // A label does not say what the product is called, so a review
          // starts here.
          autofocus: _labelReview != null,
          decoration: InputDecoration(
            labelText: S.of(context).mealNameLabel,
            border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _brandsTextController,
          decoration: InputDecoration(
            labelText: S.of(context).mealBrandsLabel,
            border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 16),
        // Optional barcode (#167). Lets the user attach a code to a custom
        // meal so a future scan recalls the saved version directly without
        // round-tripping through Open Food Facts.
        Semantics(
          identifier: 'edit-meal-barcode-input',
          child: TextFormField(
            controller: _barcodeTextController,
            decoration: InputDecoration(
              labelText: S.of(context).customMealBarcodeLabel,
              hintText: S.of(context).customMealBarcodeHint,
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
              suffixIcon: Semantics(
                identifier: 'edit-meal-barcode-scan',
                child: IconButton(
                  tooltip: S.of(context).customMealBarcodeScanButton,
                  icon: const Icon(Icons.barcode_reader),
                  onPressed: _scanBarcodeIntoField,
                ),
              ),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        // Advanced mode: quantity, unit, base-qty, and per/total toggle.
        // Simple mode omits these — the user types totals for one serving
        // and the scaffolding is hidden to reduce cognitive load (#232).
        if (!isSimple) ...[
          const SizedBox(height: 32),
          // Unit first: every quantity and nutrition value below is entered
          // in this unit, so choosing it up front keeps the form consistent
          // and lets the labels and per-100 helper reflect it (#495).
          Semantics(
            identifier: 'edit-meal-unit-selector',
            child: SegmentedButton<String>(
              segments: _mealUnitButtonSegment,
              selected: {selectedUnit ?? _units[2]},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  selectedUnit = newSelection.first;
                });
              },
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _mealQuantityTextController,
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            decoration: InputDecoration(
              labelText: '${S.of(context).mealSizeLabel} ($unitSuffix)',
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _servingQuantityTextController,
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            decoration: InputDecoration(
              labelText: '${S.of(context).servingSizeLabelMetric} ($unitSuffix)',
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _baseQuantityTextController,
            inputFormatters: CustomTextInputFormatter.doubleOnly(),
            decoration: InputDecoration(
                labelText: '${S.of(context).baseQuantityLabel} ($baseUnitSuffix)',
                errorText: _labelFlagText(null),
                errorMaxLines: 3,
                border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 48),
          Semantics(
            identifier: 'edit-meal-nutrients-mode',
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(S.of(context).mealNutrientsPerQtyLabel(
                      _getDisplayQuantity(), baseUnitSuffix)),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(S.of(context).mealNutrientsTotalLabel),
                ),
              ],
              selected: {_isTotal},
              onSelectionChanged: (Set<bool> newSelection) {
                setState(() {
                  _isTotal = newSelection.first;
                });
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _kcalTextController,
          inputFormatters: CustomTextInputFormatter.doubleOnly(),
          decoration: InputDecoration(
              errorText: _labelFlagText(LabelNutrient.energyKcal),
              errorMaxLines: 3,
              labelText:
                  '${S.of(context).mealEnergyLabel} ($energyUnitSuffix)',
              helperText: energyHelper,
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _carbsTextController,
          inputFormatters: CustomTextInputFormatter.doubleOnly(),
          decoration: InputDecoration(
              errorText: _labelFlagText(LabelNutrient.carbohydrates),
              errorMaxLines: 3,
              labelText: S.of(context).mealCarbsLabel,
              helperText: macroHelper,
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _fatTextController,
          inputFormatters: CustomTextInputFormatter.doubleOnly(),
          decoration: InputDecoration(
              errorText: _labelFlagText(LabelNutrient.fat),
              errorMaxLines: 3,
              labelText: S.of(context).mealFatLabel,
              helperText: macroHelper,
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _proteinTextController,
          inputFormatters: CustomTextInputFormatter.doubleOnly(),
          decoration: InputDecoration(
              errorText: _labelFlagText(LabelNutrient.protein),
              errorMaxLines: 3,
              labelText: S.of(context).mealProteinLabel,
              helperText: macroHelper,
              border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (!isSimple) ...[
          const SizedBox(height: 32),
          Text(
            S.of(context).micronutrientsLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final (i, field) in _microFields(context).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            _buildMicroField(
              field.controller,
              field.label,
              field.unit,
              perQtyHelper,
              errorText: _labelFlagText(field.nutrient),
            ),
          ],
        ],
        if (!_editOnly) ...[
          const SizedBox(height: 24),
          _SaveForLaterField(
            value: _saveForLater,
            onChanged: (newValue) {
              setState(() {
                _saveForLater = newValue;
              });
            },
          ),
        ],
      ],
    );
  }

  /// The Advanced-mode micronutrient fields, in label order: fats,
  /// cholesterol and sodium, carbohydrate parts, vitamins, minerals.
  List<
    ({
      TextEditingController controller,
      String label,
      String unit,
      LabelNutrient nutrient,
    })
  >
  _microFields(BuildContext context) {
    final s = S.of(context);
    return [
      (controller: _saturatedFatTextController, label: s.saturatedFatLabel, unit: 'g', nutrient: LabelNutrient.saturatedFat),
      (controller: _transFatTextController, label: s.transFatLabel, unit: 'g', nutrient: LabelNutrient.transFat),
      (controller: _monounsaturatedFatTextController, label: s.monounsaturatedFatLabel, unit: 'g', nutrient: LabelNutrient.monounsaturatedFat),
      (controller: _polyunsaturatedFatTextController, label: s.polyunsaturatedFatLabel, unit: 'g', nutrient: LabelNutrient.polyunsaturatedFat),
      (controller: _cholesterolTextController, label: s.cholesterolLabel, unit: 'mg', nutrient: LabelNutrient.cholesterol),
      (controller: _sodiumTextController, label: s.sodiumLabel, unit: 'mg', nutrient: LabelNutrient.sodium),
      (controller: _fiberTextController, label: s.fiberLabel, unit: 'g', nutrient: LabelNutrient.fiber),
      (controller: _sugarsTextController, label: s.sugarLabel, unit: 'g', nutrient: LabelNutrient.sugars),
      (controller: _vitaminATextController, label: s.vitaminALabel, unit: 'µg', nutrient: LabelNutrient.vitaminA),
      (controller: _vitaminCTextController, label: s.vitaminCLabel, unit: 'mg', nutrient: LabelNutrient.vitaminC),
      (controller: _vitaminDTextController, label: s.vitaminDLabel, unit: 'µg', nutrient: LabelNutrient.vitaminD),
      (controller: _vitaminB6TextController, label: s.vitaminB6Label, unit: 'mg', nutrient: LabelNutrient.vitaminB6),
      (controller: _vitaminB12TextController, label: s.vitaminB12Label, unit: 'µg', nutrient: LabelNutrient.vitaminB12),
      (controller: _niacinTextController, label: s.niacinLabel, unit: 'mg', nutrient: LabelNutrient.niacin),
      (controller: _calciumTextController, label: s.calciumLabel, unit: 'mg', nutrient: LabelNutrient.calcium),
      (controller: _ironTextController, label: s.ironLabel, unit: 'mg', nutrient: LabelNutrient.iron),
      (controller: _potassiumTextController, label: s.potassiumLabel, unit: 'mg', nutrient: LabelNutrient.potassium),
      (controller: _magnesiumTextController, label: s.magnesiumLabel, unit: 'mg', nutrient: LabelNutrient.magnesium),
      (controller: _zincTextController, label: s.zincLabel, unit: 'mg', nutrient: LabelNutrient.zinc),
      (controller: _phosphorusTextController, label: s.phosphorusLabel, unit: 'mg', nutrient: LabelNutrient.phosphorus),
    ];
  }

  Widget _buildMicroField(
    TextEditingController controller,
    String label,
    String unit,
    String? helperText, {
    String? errorText,
  }) {
    return TextFormField(
      controller: controller,
      inputFormatters: CustomTextInputFormatter.doubleOnly(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        helperText: helperText,
        // A highlight, not a validation: nothing reads it on save.
        errorText: errorText,
        errorMaxLines: 3,
        border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }

  /// Returns "0" for empty / whitespace-only text, otherwise the original
  /// string. Used on the Simple-mode save path so a blank macro field is
  /// stored as an explicit 0 — see the surrounding comment at the call
  /// site for why "empty means zero" is the right default in Simple mode.
  String _simpleFieldOrZero(String text) {
    return text.trim().isEmpty ? '0' : text;
  }

  String _getDisplayQuantity() {
    final text = _baseQuantityTextController.text;
    return text.isEmpty ? baseQuantity : text;
  }

  /// The unit shown in the Advanced-mode field labels and the per-100
  /// helper. It follows the unit selector (the first Advanced field) and the
  /// user's metric/imperial setting, built from the existing localized unit
  /// tokens so locales like uk/zh keep their own notation (#495).
  String _massUnitSuffix(BuildContext context) {
    final s = S.of(context);
    final unit = selectedUnit ?? _units[2];
    if (_usesImperialUnits) {
      switch (unit) {
        case 'g':
          return s.ozUnit;
        case 'ml':
          return s.flOzUnit;
        default:
          return '${s.ozUnit}/${s.flOzUnit}';
      }
    }
    switch (unit) {
      case 'g':
        return s.gramUnit;
      case 'ml':
        return s.milliliterUnit;
      default:
        return s.gramMilliliterUnit;
    }
  }

  /// Set while a save runs, so a second tap on Save before the first one has
  /// navigated away does nothing. A second run would build the meal again
  /// from the same pre-edit [_mealEntity]: after a barcode clear that is a
  /// fresh internal id matching no entry, and the library got a copy.
  bool _saving = false;

  Future<void> _onSavePressed(bool usesImperialUnits) async {
    if (_saving) return;
    _saving = true;
    try {
      await _save(usesImperialUnits);
    } finally {
      _saving = false;
    }
  }

  Future<void> _save(bool usesImperialUnits) async {
    try {
      // Validate meal name: non-empty and contains at least one letter (#211, #214)
      if (!FoodNameValidator.isValid(_nameTextController.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).mealNameValidationError)));
        return;
      }

      // Validate barcode shape if the user typed or scanned one (#167).
      // Empty is fine — the field is optional. 8-14 digits required;
      // EAN-13 check digit must verify for codes of that exact length.
      final rawBarcode = _barcodeTextController.text.trim();
      if (rawBarcode.isNotEmpty) {
        if (!isBarcodeFormatValid(rawBarcode)) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context).customMealBarcodeInvalid)));
          return;
        }
        if (!isEan13CheckDigitValid(rawBarcode)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(S.of(context).barcodeInvalidEan13CheckDigit)));
          return;
        }
      }

      final MealEntity newMealEntity;
      if (_formMode == CustomMealFormMode.simple) {
        // Simple mode (#232): the user typed totals for one serving. Convert
        // kJ → kcal if needed, then store using baseQuantity="100" so the
        // entered values land in the per-100g fields without scaling.
        // The earlier "1" here meant factorTo100g resolved to 100, which
        // silently multiplied every typed value by 100 on save — 100 kcal
        // round-tripped to 10000 kcal once the meal was reloaded.
        final usesKjOnSave =
            Provider.of<EnergyUnitProvider>(context, listen: false)
                .usesKilojoules;
        final enteredEnergyRaw = double.tryParse(_kcalTextController.text);
        final kcalTextForSimple = (enteredEnergyRaw != null && usesKjOnSave)
            ? UnitCalc.kjToKcal(enteredEnergyRaw).toStringAsFixed(1)
            : _kcalTextController.text;
        // Treat empty Simple-mode macro fields as an explicit zero rather
        // than null. A user filling out a custom meal in Simple mode is the
        // source of truth for that food — many real foods genuinely have
        // zero of one macro (oil, plain meat, egg whites) and leaving the
        // field blank should mean "this food has none", not "I don't know".
        // The previous behaviour persisted null on the per-100g slot, which
        // the meal-detail sheet's _hasRequiredProductInfoMissing() then
        // blocked at log time with a "Product missing required kcal or
        // macronutrients information" message that contradicted the on-
        // screen 0.0 display.
        newMealEntity = _editMealBloc.createNewMealEntity(
          _mealEntity,
          _nameTextController.text,
          _brandsTextController.text,
          "100",
          "100",
          "100",
          _units[2], // g/ml
          _simpleFieldOrZero(kcalTextForSimple),
          _simpleFieldOrZero(_carbsTextController.text),
          _simpleFieldOrZero(_fatTextController.text),
          _simpleFieldOrZero(_proteinTextController.text),
          barcodeOverride: rawBarcode,
          localImagePathOverride: _localImagePath,
          clearLocalImagePath: _localImageCleared && _localImagePath == null,
        );
      } else {
        // A label review's fields hold one Label Serving. Without its
        // weight the save would read them as per 100 g.
        final reviewGrams = double.tryParse(_baseQuantityTextController.text);
        if (_labelReview != null &&
            (reviewGrams == null || !reviewGrams.isFinite || reviewGrams <= 0)) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(S.of(context).labelFlagServingWeightMissing)));
          return;
        }
        // Advanced mode: validate nutritional consistency (#213).
        final baseQty =
            double.tryParse(_baseQuantityTextController.text) ?? 100.0;
        // The energy field is rendered in the user's active unit (#177
        // follow-up). Parse it as that unit and immediately fold it back
        // to kcal — every downstream check, every persisted value, and
        // every comparison expects kcal.
        final usesKjOnSave =
            Provider.of<EnergyUnitProvider>(context, listen: false)
                .usesKilojoules;
        final enteredEnergyRaw = double.tryParse(_kcalTextController.text);
        final enteredKcal = enteredEnergyRaw == null
            ? null
            : (usesKjOnSave
                ? double.parse(
                    UnitCalc.kjToKcal(enteredEnergyRaw).toStringAsFixed(1))
                : enteredEnergyRaw);
        final enteredCarbs = double.tryParse(_carbsTextController.text);
        final enteredFat = double.tryParse(_fatTextController.text);
        final enteredProtein = double.tryParse(_proteinTextController.text);

        for (final entry in {
          'Carbs': enteredCarbs,
          'Fat': enteredFat,
          'Protein': enteredProtein,
        }.entries) {
          if (entry.value != null && entry.value! > baseQty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '${entry.key} cannot exceed base quantity (${baseQty}g/ml)')));
            return;
          }
        }

        if (enteredCarbs != null &&
            enteredFat != null &&
            enteredProtein != null) {
          final totalMacros = enteredCarbs + enteredFat + enteredProtein;
          if (totalMacros > baseQty * 1.05) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Total macros (${totalMacros.toStringAsFixed(1)}g) exceed base quantity (${baseQty.toStringAsFixed(0)}g)')));
            return;
          }
        }

        if (enteredKcal != null && enteredKcal > baseQty * 9) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Kcal value seems too high for ${baseQty.toStringAsFixed(0)}g/ml')));
          return;
        }

        // Atwater consistency check (#213): warn if entered kcal disagrees
        // with 4·carbs + 4·protein + 9·fat by more than 5%. Non-blocking.
        if (enteredKcal != null &&
            enteredCarbs != null &&
            enteredFat != null &&
            enteredProtein != null) {
          final expectedKcal =
              4 * enteredCarbs + 4 * enteredProtein + 9 * enteredFat;
          final delta = (enteredKcal - expectedKcal).abs();
          final ceiling = math.max(enteredKcal.abs(), expectedKcal.abs());
          if (ceiling > 0 && delta > 0.05 * ceiling) {
            final shouldSaveAnyway = await _showAtwaterWarningDialog();
            if (!mounted) return;
            if (shouldSaveAnyway != true) {
              return;
            }
          }
        }

        // Convert meal size back to metric units if necessary
        final mealUnitForConversion =
            selectedUnit ?? _mealEntity.mealUnit ?? '0';
        final mealQuantity = usesImperialUnits
            ? _convertToMetric(
                _mealQuantityTextController.text, mealUnitForConversion)
            : _mealQuantityTextController.text;
        // The serving quantity is loaded and edited in imperial too (see the
        // initial _convertToImperial above), so it has to fold back to metric
        // on save the same way the meal size does — otherwise an imperial
        // serving value is stored raw into a metric field and drifts further
        // on every reopen (#495).
        final servingQuantity = usesImperialUnits
            ? _convertToMetric(
                _servingQuantityTextController.text, mealUnitForConversion)
            : _servingQuantityTextController.text;

        // Convert total → per-base-qty if in total input mode. kcalText
        // uses the already-kcal-folded value so kJ entries are persisted
        // in kcal regardless of the display unit.
        String kcalText = enteredKcal == null
            ? _kcalTextController.text
            : enteredKcal.toStringOrEmpty();
        String carbsText = _carbsTextController.text;
        String fatText = _fatTextController.text;
        String proteinText = _proteinTextController.text;
        String fiberText = _fiberTextController.text;
        String saturatedFatText = _saturatedFatTextController.text;
        String sugarsText = _sugarsTextController.text;
        String sodiumText = _sodiumTextController.text;
        String calciumText = _calciumTextController.text;
        String ironText = _ironTextController.text;
        String potassiumText = _potassiumTextController.text;
        String magnesiumText = _magnesiumTextController.text;
        String vitaminDText = _vitaminDTextController.text;
        String vitaminB12Text = _vitaminB12TextController.text;
        String transFatText = _transFatTextController.text;
        String cholesterolText = _cholesterolTextController.text;
        String monounsaturatedFatText = _monounsaturatedFatTextController.text;
        String polyunsaturatedFatText = _polyunsaturatedFatTextController.text;
        String vitaminAText = _vitaminATextController.text;
        String vitaminCText = _vitaminCTextController.text;
        String vitaminB6Text = _vitaminB6TextController.text;
        String niacinText = _niacinTextController.text;
        String zincText = _zincTextController.text;
        String phosphorusText = _phosphorusTextController.text;
        if (_isTotal) {
          final mealQty = double.tryParse(mealQuantity) ?? 0.0;
          final baseQtyForConversion =
              double.tryParse(_baseQuantityTextController.text) ?? 100.0;
          if (mealQty > 0) {
            String convertTotal(String text) {
              final v = double.tryParse(text);
              if (v == null) return text;
              return ((v / mealQty) * baseQtyForConversion).toString();
            }

            kcalText = convertTotal(kcalText);
            carbsText = convertTotal(carbsText);
            fatText = convertTotal(fatText);
            proteinText = convertTotal(proteinText);
            fiberText = convertTotal(fiberText);
            saturatedFatText = convertTotal(saturatedFatText);
            sugarsText = convertTotal(sugarsText);
            sodiumText = convertTotal(sodiumText);
            calciumText = convertTotal(calciumText);
            ironText = convertTotal(ironText);
            potassiumText = convertTotal(potassiumText);
            magnesiumText = convertTotal(magnesiumText);
            vitaminDText = convertTotal(vitaminDText);
            vitaminB12Text = convertTotal(vitaminB12Text);
            transFatText = convertTotal(transFatText);
            cholesterolText = convertTotal(cholesterolText);
            monounsaturatedFatText = convertTotal(monounsaturatedFatText);
            polyunsaturatedFatText = convertTotal(polyunsaturatedFatText);
            vitaminAText = convertTotal(vitaminAText);
            vitaminCText = convertTotal(vitaminCText);
            vitaminB6Text = convertTotal(vitaminB6Text);
            niacinText = convertTotal(niacinText);
            zincText = convertTotal(zincText);
            phosphorusText = convertTotal(phosphorusText);
          }
        }

        newMealEntity = _editMealBloc.createNewMealEntity(
          _mealEntity,
          _nameTextController.text,
          _brandsTextController.text,
          mealQuantity,
          servingQuantity,
          _baseQuantityTextController.text,
          selectedUnit,
          kcalText,
          carbsText,
          fatText,
          proteinText,
          fiberText: fiberText,
          saturatedFatText: saturatedFatText,
          sugarsText: sugarsText,
          sodiumText: sodiumText,
          calciumText: calciumText,
          ironText: ironText,
          potassiumText: potassiumText,
          magnesiumText: magnesiumText,
          vitaminDText: vitaminDText,
          vitaminB12Text: vitaminB12Text,
          transFatText: transFatText,
          cholesterolText: cholesterolText,
          monounsaturatedFatText: monounsaturatedFatText,
          polyunsaturatedFatText: polyunsaturatedFatText,
          vitaminAText: vitaminAText,
          vitaminCText: vitaminCText,
          vitaminB6Text: vitaminB6Text,
          niacinText: niacinText,
          zincText: zincText,
          phosphorusText: phosphorusText,
          barcodeOverride: rawBarcode,
          localImagePathOverride: _localImagePath,
          clearLocalImagePath: _localImageCleared && _localImagePath == null,
        );
      }

      // Persist custom meal template (#267). Skipped for one-off entries
      // (#249) when the user has turned off "Save for next time" — the
      // intake itself is still logged below, but no template is kept.
      final shouldPersistTemplate = _editOnly || _saveForLater;
      if (newMealEntity.source == MealSourceEntity.custom &&
          shouldPersistTemplate) {
        await _editMealBloc.saveCustomMeal(
          newMealEntity,
          previous: _mealEntity,
        );
      }

      if (!mounted) return;
      if (_editOnly) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(
          NavigationOptions.mealDetailRoute,
          namedRouteOrFirst(NavigationOptions.addMealRoute),
          arguments: MealDetailScreenArguments(
            newMealEntity,
            _intakeTypeEntity,
            _day,
            usesImperialUnits,
            logTray: _logTray,
          ),
        );
      }
    } catch (exception, stacktrace) {
      log.warning("Error while creating new meal entity");
      Sentry.captureException(exception, stackTrace: stacktrace);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.of(context).errorMealSave)));
    }
  }

  /// Push a lightweight `MobileScanner` page that returns the first product
  /// barcode it sees, then drop the value into the barcode TextField. The
  /// scan-time validator on the field handles bad codes (8–14 digits,
  /// EAN-13 check digit) — we don't double-validate here so the user can
  /// see and edit the raw scanned value before saving.
  Future<void> _scanBarcodeIntoField() async {
    log.fine('Opening edit-meal barcode scanner');
    final navigator = Navigator.of(context);
    final result = await navigator.push<String?>(
      MaterialPageRoute(builder: (_) => const _EditMealBarcodeScanPage()),
    );
    log.fine('Edit-meal barcode scanner returned: $result');
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _barcodeTextController.text = result;
    });
    log.fine('Barcode text controller after set: ${_barcodeTextController.text}');
  }

  Widget _buildRemoteMealImage() {
    return ClipOval(
      child: CachedNetworkImage(
        cacheManager: locator<CacheManager>(),
        width: 120,
        height: 120,
        placeholder: (context, string) => const DefaultMealImage(),
        errorWidget: (context, exception, stacktrace) =>
            const DefaultMealImage(),
        fit: BoxFit.cover,
        imageUrl: _mealEntity.mainImageUrl ?? "",
      ),
    );
  }

  Future<void> _onPickMealImage(ImageSource source) async {
    // For custom meals the entity's `code` is a stable UUID seeded at
    // MealEntity.empty() time; we use it as the photo's filename so a
    // re-edit of the same meal lands at the same on-disk slug. If the
    // user has typed a real barcode into the code field, fall back to
    // the entity's original code rather than the in-progress text — the
    // photo identity is the meal, not the barcode.
    final ownerId = _mealEntity.code;
    if (ownerId == null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source);
      if (picked == null) return;
      final relative = await UserImageStorage.importFrom(
        kind: UserImageKind.meal,
        ownerId: ownerId,
        sourcePath: picked.path,
      );
      // Bust the in-memory Image.file cache so the new picture shows up
      // immediately instead of redrawing previous bytes for this path.
      FileImage(File(await UserImageStorage.absolutePath(relative))).evict();
      if (!mounted) return;
      setState(() {
        _localImagePath = relative;
        _localImageCleared = false;
      });
    } catch (e, st) {
      // Pick / encode failure is rare; surfacing a SnackBar from inside
      // the picker flow felt noisier than the failure deserves. The user
      // can simply tap the picker again.
      log.warning('Failed to pick meal image', e, st);
    }
  }

  Future<void> _onRemoveMealImage() async {
    final current = _localImagePath;
    if (current == null) return;
    await UserImageStorage.delete(current);
    if (!mounted) return;
    setState(() {
      _localImagePath = null;
      _localImageCleared = true;
    });
  }

  Future<bool?> _showAtwaterWarningDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).inconsistentNutritionWarningTitle),
          content: Text(S.of(dialogContext).inconsistentNutritionWarningBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).inconsistentNutritionWarningEdit),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                S.of(dialogContext).inconsistentNutritionWarningSaveAnyway,
              ),
            ),
          ],
        );
      },
    );
  }

  String? _switchButtonUnit(String? unit) {
    if (!_units.contains(unit)) {
      return _units[2]; // Default to g/ml
    }
    return unit;
  }

  String _convertToImperial(String value, String unit) {
    final double quantityValue = double.tryParse(value) ?? 0.0;
    switch (unit) {
      case 'g':
        return (UnitCalc.gToOz(quantityValue)).toStringAsFixed(2);
      case 'ml':
        return (UnitCalc.mlToFlOz(quantityValue)).toStringAsFixed(2);
      default:
        return value;
    }
  }

  String _convertToMetric(String value, String unit) {
    final double quantityValue = double.tryParse(value) ?? 0.0;
    switch (unit) {
      case 'g':
        return (UnitCalc.ozToG(quantityValue)).toStringAsFixed(2);
      case 'ml':
        return (UnitCalc.flOzToMl(quantityValue)).toStringAsFixed(2);
      default:
        return value;
    }
  }
}

class EditMealScreenArguments {
  final DateTime day;
  final MealEntity mealEntity;
  final IntakeTypeEntity intakeTypeEntity;
  final bool usesImperialUnits;
  final bool editOnly;

  /// The add-food screen's "To log" list, handed on to the detail screen a
  /// new food opens in so that it adds there instead of logging.
  final LogTray? logTray;

  /// Set when the meal was read from a nutrition label photo
  /// (docs/adr/0003): the form opens on the label's own numbers, per Label
  /// Serving, with the failed checks highlighted.
  final LabelReview? labelReview;

  EditMealScreenArguments(
    this.day,
    this.mealEntity,
    this.intakeTypeEntity,
    this.usesImperialUnits, {
    this.editOnly = false,
    this.logTray,
    this.labelReview,
  });
}

/// "Save for next time" toggle shown on the create-and-log path (#249).
/// Defaults to off: the intake is logged today, and the user opts in here
/// to also keep the meal as a reusable template in the custom-meal list.
/// Leaving it off is the right call for one-off entries like a friend's
/// homemade dish or a restaurant meal that won't come back round.
class _SaveForLaterField extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SaveForLaterField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return AppCard(
      color: palette.surfaceMuted,
      onTap: () => onChanged(!value),
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing16,
        Dimens.spacing12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            identifier: 'edit-meal-save-for-later',
            child: Checkbox(
              value: value,
              onChanged: (newValue) => onChanged(newValue ?? false),
            ),
          ),
          const SizedBox(width: Dimens.spacing4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.recipeSaveForLaterLabel,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Dimens.spacing4),
                  Text(
                    s.recipeSaveForLaterDescription,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal camera page used by [_EditMealScreenState._scanBarcodeIntoField].
/// Pops itself with the first product barcode it detects, or returns null
/// when the user taps the back button. We keep this private to the edit-meal
/// flow rather than reusing the full ScannerScreen because that screen runs
/// its own lookup-and-route logic that wouldn't fit a "give me the raw
/// string" use case.
class _EditMealBarcodeScanPage extends StatefulWidget {
  const _EditMealBarcodeScanPage();

  @override
  State<_EditMealBarcodeScanPage> createState() =>
      _EditMealBarcodeScanPageState();
}

class _EditMealBarcodeScanPageState extends State<_EditMealBarcodeScanPage>
    with WidgetsBindingObserver {
  static final _log = Logger('EditMealBarcodeScan');
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_controller.stop());
      case AppLifecycleState.resumed:
        unawaited(_controller.start());
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    _log.fine('onDetect: ${capture.barcodes.length} barcodes; '
        'types=${capture.barcodes.map((b) => b.type.name).toList()}; '
        'rawValues=${capture.barcodes.map((b) => b.rawValue).toList()}');
    if (_done) return;
    for (final b in capture.barcodes) {
      // Accept any non-null raw value. ML Kit's type classifier is reliable
      // for QR / data-matrix but sometimes labels a valid retail barcode as
      // `BarcodeType.unknown` depending on print quality and camera angle —
      // filtering strictly by `BarcodeType.product` was silently dropping
      // those. The save-time validator on the edit-meal screen does the
      // real "is this a valid barcode" check.
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _log.fine('Popping with rawValue=$raw (type=${b.type.name})');
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).customMealBarcodeScanButton)),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}

/// Says where a review's numbers came from, and what to do with them.
class _LabelReviewBanner extends StatelessWidget {
  final bool flagged;

  const _LabelReviewBanner({required this.flagged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Semantics(
      identifier: 'edit-meal-label-review-banner',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: Dimens.borderRadiusM,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                flagged
                    ? s.labelReviewBannerFlagged
                    : s.labelReviewBanner,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
