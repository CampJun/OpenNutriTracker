import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_interpreter_exception.dart';

/// The units a US nutrition label states its amounts in.
enum LabelUnit { g, mg, mcg, kcal }

/// One amount a US "Nutrition Facts" label can print, in the unit it prints
/// it in.
///
/// [wireName] is the key the model answers with, and its suffix names the
/// unit on purpose: in the prototype a model asked for `sodium` with no unit
/// in the key had to guess, and `sodiumMg` leaves nothing to guess.
///
/// [dailyValue] is the FDA Daily Value (21 CFR 101.9(c), the 2016 values),
/// in the same unit. It is what the %DV check divides by. Null where the
/// label carries no %DV.
enum LabelNutrient {
  energyKcal('energyKcal', LabelUnit.kcal),
  fat('fat', LabelUnit.g, 78),
  saturatedFat('saturatedFat', LabelUnit.g, 20),
  transFat('transFat', LabelUnit.g),
  monounsaturatedFat('monounsaturatedFat', LabelUnit.g),
  polyunsaturatedFat('polyunsaturatedFat', LabelUnit.g),
  cholesterol('cholesterolMg', LabelUnit.mg, 300),
  sodium('sodiumMg', LabelUnit.mg, 2300),
  carbohydrates('carbohydrates', LabelUnit.g, 275),
  fiber('fiber', LabelUnit.g, 28),
  sugars('sugars', LabelUnit.g),

  /// Read for the checks only. The app stores no added-sugars value, so it
  /// never reaches a Custom Food.
  addedSugars('addedSugars', LabelUnit.g, 50),
  protein('protein', LabelUnit.g, 50),
  vitaminA('vitaminAMcg', LabelUnit.mcg, 900),
  vitaminC('vitaminCMg', LabelUnit.mg, 90),
  vitaminD('vitaminDMcg', LabelUnit.mcg, 20),
  vitaminB6('vitaminB6Mg', LabelUnit.mg, 1.7),
  vitaminB12('vitaminB12Mcg', LabelUnit.mcg, 2.4),
  niacin('niacinMg', LabelUnit.mg, 16),
  calcium('calciumMg', LabelUnit.mg, 1300),
  iron('ironMg', LabelUnit.mg, 18),
  magnesium('magnesiumMg', LabelUnit.mg, 420),
  zinc('zincMg', LabelUnit.mg, 11),
  phosphorus('phosphorusMg', LabelUnit.mg, 1250),
  potassium('potassiumMg', LabelUnit.mg, 4700);

  final String wireName;
  final LabelUnit unit;
  final double? dailyValue;

  const LabelNutrient(this.wireName, this.unit, [this.dailyValue]);

  /// The key the model answers this nutrient's printed %DV with.
  String get dailyValueWireName => '${wireName}DV';

  /// The largest amount one serving can plausibly state. A reply above it
  /// is a misread (a %DV in the amount slot, a lost decimal point) and is
  /// dropped rather than shown.
  double get ceiling => switch (unit) {
    LabelUnit.kcal => 5000,
    LabelUnit.g => 1000,
    LabelUnit.mg => 100000,
    LabelUnit.mcg => 100000,
  };
}

/// What one nutrition label states, per Label Serving, in label units.
///
/// Every value is something the model copied off the label. None is
/// computed, and a nutrient printed only as a %DV has no amount here.
class NutritionLabel {
  /// The Label Serving as printed, such as "2 Tbsp (31g)".
  final String? servingSize;

  /// The Label Serving's weight. Null when the label gives none, and then
  /// nothing can be converted to per 100 g until the user types it.
  final double? servingGrams;

  final double? servingsPerContainer;

  final Map<LabelNutrient, double> amounts;

  /// The %DV printed beside an amount. Used by the checks, never stored.
  final Map<LabelNutrient, double> dailyValuePercents;

  const NutritionLabel({
    this.servingSize,
    this.servingGrams,
    this.servingsPerContainer,
    this.amounts = const {},
    this.dailyValuePercents = const {},
  });

  /// True when the reply held no nutrition facts at all: the photo was not
  /// a label, or nothing on it was legible.
  bool get isEmpty => amounts.isEmpty && servingGrams == null;
}

const nutritionLabelToolName = 'record_nutrition_label';

const nutritionLabelToolDescription =
    'Record the amounts printed on a nutrition facts label.';

/// What the label reader tells the model. The rules are the ones the
/// prototype measured (docs/adr/0003): copy, never compute.
const nutritionLabelSystemPrompt = '''
You read US "Nutrition Facts" labels and record them with the tool.
Rules:
- Record values PER SERVING. If the label also has a per-container column,
  ignore that column.
- Copy amounts exactly as printed. Never compute, estimate, or round.
- Each key names its unit: grams unless it ends in Mg (milligrams) or Mcg
  (micrograms); energyKcal is calories.
- Never convert a %DV into an amount. A nutrient printed only as a
  percentage gets no amount; record the percentage in its DV key.
- Leave out anything not printed or not legible.
- "<1g" is 0.5. "about 15" servings is 15.
- servingGrams is the gram weight of one serving, as printed.''';

/// The text sent with the photo.
const nutritionLabelPhotoPrompt = 'Record this nutrition label.';

/// The schema the model is held to. Like `mealItemsToolSchema` it is a
/// hint, not the enforcement: [nutritionLabelFromJson] re-checks every
/// value in Dart.
final Map<String, Object> nutritionLabelToolSchema = {
  'type': 'object',
  'properties': {
    'servingSize': {
      'type': 'string',
      'description': 'The serving size as printed, e.g. "2 Tbsp (31g)".',
    },
    'servingGrams': {
      'type': 'number',
      'description': 'Gram weight of one serving.',
    },
    'servingsPerContainer': {'type': 'number'},
    for (final n in LabelNutrient.values) ...{
      n.wireName: {'type': 'number'},
      if (n.dailyValue != null)
        n.dailyValueWireName: {
          'type': 'number',
          'description': 'Printed %DV for ${n.wireName}, as a number.',
        },
    },
  },
  'additionalProperties': false,
};

/// Reads the tool call's arguments. Raises when they are not an object at
/// all; drops any single value that is not a plausible number.
NutritionLabel nutritionLabelFromJson(Object? input) {
  if (input is! Map) {
    throw const MealInterpreterException('tool call has no arguments');
  }

  double? number(Object? raw) {
    final value = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s.replaceAll(',', '.').trim()),
      _ => null,
    };
    return (value != null && value.isFinite && value >= 0) ? value : null;
  }

  double? within(Object? raw, double max, {bool positive = false}) {
    final value = number(raw);
    if (value == null || value > max || (positive && value == 0)) return null;
    return value;
  }

  final servingSize = input['servingSize'];
  return NutritionLabel(
    servingSize: servingSize is String && servingSize.trim().isNotEmpty
        ? servingSize.trim()
        : null,
    servingGrams: within(input['servingGrams'], 5000, positive: true),
    servingsPerContainer: within(
      input['servingsPerContainer'],
      1000,
      positive: true,
    ),
    amounts: {
      for (final n in LabelNutrient.values)
        n: ?within(input[n.wireName], n.ceiling),
    },
    dailyValuePercents: {
      for (final n in LabelNutrient.values)
        if (n.dailyValue != null) n: ?within(input[n.dailyValueWireName], 1000),
    },
  );
}

/// Why a value on the review screen deserves a second look.
enum LabelFlagKind {
  /// The amount disagrees with its own printed %DV.
  dailyValueMismatch,

  /// Calories disagree with 9·fat + 4·carbohydrates + 4·protein.
  energyMismatch,

  /// A part is larger than its total: saturated fat above fat, added
  /// sugars above sugars.
  partExceedsTotal,

  /// Fat, carbohydrates and protein weigh more than the serving.
  macrosExceedServing,

  /// No serving weight, so nothing can be converted to per 100 g.
  servingWeightMissing,
}

/// One check that failed. Never changes a value: it says where to look.
class LabelFlag {
  /// The field the flag is shown on. Null means the serving weight.
  final LabelNutrient? nutrient;
  final LabelFlagKind kind;

  /// [LabelFlagKind.dailyValueMismatch]: the printed %DV and the amount it
  /// implies.
  final double? printedPercent;
  final double? impliedAmount;

  /// [LabelFlagKind.energyMismatch]: the calories the macros add up to.
  final double? computedKcal;

  /// [LabelFlagKind.partExceedsTotal]: the part that is too large, when it
  /// is not the field the flag is shown on (added sugars has no field).
  final LabelNutrient? part;
  final double? partAmount;

  const LabelFlag(
    this.nutrient,
    this.kind, {
    this.printedPercent,
    this.impliedAmount,
    this.computedKcal,
    this.part,
    this.partAmount,
  });
}

/// The label's own arithmetic, checked. Labels round, so every comparison
/// has slack; labels are also sometimes wrong, which is why a flag never
/// blocks or corrects anything.
List<LabelFlag> checkNutritionLabel(NutritionLabel label) {
  final a = label.amounts;
  final flags = <LabelFlag>[];

  for (final entry in label.dailyValuePercents.entries) {
    final nutrient = entry.key;
    final printed = entry.value;
    final amount = a[nutrient];
    final dv = nutrient.dailyValue;
    if (amount == null || dv == null) continue;
    final implied = amount / dv * 100;
    // Two points or 15%, whichever is larger: wide enough for the FDA's
    // rounding of both the amount and the percentage, narrow enough that
    // 1.0 mg of iron printed beside 10% (which is 1.8 mg) is caught.
    if ((implied - printed).abs() > _max(2.5, 0.15 * printed)) {
      flags.add(
        LabelFlag(
          nutrient,
          LabelFlagKind.dailyValueMismatch,
          printedPercent: printed,
          impliedAmount: printed * dv / 100,
        ),
      );
    }
  }

  final kcal = a[LabelNutrient.energyKcal];
  final fat = a[LabelNutrient.fat];
  final carbs = a[LabelNutrient.carbohydrates];
  final protein = a[LabelNutrient.protein];
  if (kcal != null && fat != null && carbs != null && protein != null) {
    final computed = 9 * fat + 4 * carbs + 4 * protein;
    if ((computed - kcal).abs() > _max(20, 0.2 * kcal)) {
      flags.add(
        LabelFlag(
          LabelNutrient.energyKcal,
          LabelFlagKind.energyMismatch,
          computedKcal: computed,
        ),
      );
    }
  }

  void partOf(LabelNutrient part, LabelNutrient total, LabelNutrient shownOn) {
    final p = a[part];
    final t = a[total];
    if (p != null && t != null && p > t) {
      flags.add(
        LabelFlag(
          shownOn,
          LabelFlagKind.partExceedsTotal,
          part: part,
          partAmount: p,
        ),
      );
    }
  }

  partOf(
    LabelNutrient.saturatedFat,
    LabelNutrient.fat,
    LabelNutrient.saturatedFat,
  );
  partOf(LabelNutrient.transFat, LabelNutrient.fat, LabelNutrient.transFat);
  partOf(LabelNutrient.addedSugars, LabelNutrient.sugars, LabelNutrient.sugars);
  partOf(LabelNutrient.fiber, LabelNutrient.carbohydrates, LabelNutrient.fiber);
  partOf(
    LabelNutrient.sugars,
    LabelNutrient.carbohydrates,
    LabelNutrient.sugars,
  );

  final grams = label.servingGrams;
  if (grams == null) {
    flags.add(const LabelFlag(null, LabelFlagKind.servingWeightMissing));
  } else if (fat != null &&
      carbs != null &&
      protein != null &&
      fat + carbs + protein > grams * 1.05) {
    flags.add(const LabelFlag(null, LabelFlagKind.macrosExceedServing));
  }
  return flags;
}

double _max(double a, double b) => a > b ? a : b;

/// A Custom Food holding what [label] states, ready for the review screen.
///
/// Nutrients are stored per 100 g, scaled by the Label Serving's weight.
/// Without a weight they are left empty here; the review screen shows the
/// label's own numbers and the user supplies the weight.
MealEntity customFoodFromLabel(NutritionLabel label, {String? barcode}) {
  final grams = label.servingGrams;
  final per100 = grams == null ? null : 100 / grams;
  double? v(LabelNutrient n) {
    final amount = label.amounts[n];
    return (amount == null || per100 == null) ? null : amount * per100;
  }

  final servings = label.servingsPerContainer;
  final empty = MealEntity.empty();
  return MealEntity(
    code: barcode ?? empty.code,
    name: null,
    url: null,
    mealQuantity: (grams != null && servings != null)
        ? _trim(grams * servings)
        : null,
    mealUnit: 'g',
    servingQuantity: grams,
    servingUnit: 'g',
    servingSize: label.servingSize ?? '',
    nutriments: MealNutrimentsEntity(
      energyKcal100: v(LabelNutrient.energyKcal),
      carbohydrates100: v(LabelNutrient.carbohydrates),
      fat100: v(LabelNutrient.fat),
      proteins100: v(LabelNutrient.protein),
      sugars100: v(LabelNutrient.sugars),
      saturatedFat100: v(LabelNutrient.saturatedFat),
      fiber100: v(LabelNutrient.fiber),
      monounsaturatedFat100: v(LabelNutrient.monounsaturatedFat),
      polyunsaturatedFat100: v(LabelNutrient.polyunsaturatedFat),
      transFat100: v(LabelNutrient.transFat),
      cholesterol100: v(LabelNutrient.cholesterol),
      sodium100: v(LabelNutrient.sodium),
      potassium100: v(LabelNutrient.potassium),
      magnesium100: v(LabelNutrient.magnesium),
      calcium100: v(LabelNutrient.calcium),
      iron100: v(LabelNutrient.iron),
      zinc100: v(LabelNutrient.zinc),
      phosphorus100: v(LabelNutrient.phosphorus),
      vitaminA100: v(LabelNutrient.vitaminA),
      vitaminC100: v(LabelNutrient.vitaminC),
      vitaminD100: v(LabelNutrient.vitaminD),
      vitaminB6100: v(LabelNutrient.vitaminB6),
      vitaminB12100: v(LabelNutrient.vitaminB12),
      niacin100: v(LabelNutrient.niacin),
    ),
    source: MealSourceEntity.custom,
  );
}

String _trim(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// One request to a model that reads a label photo.
///
/// Raises [MealInterpreterException] for every ordinary failure, with the
/// same failure kinds as meal photos, so the screens word them the same way.
abstract interface class NutritionLabelApi {
  Future<NutritionLabel> read({
    required String mediaType,
    required String base64Data,
  });
}

/// A label read on its way to the review screen: what it states, and the
/// checks that failed.
class LabelReview {
  final NutritionLabel label;
  final List<LabelFlag> flags;

  const LabelReview(this.label, this.flags);
}
