import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_interpreter_exception.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';

/// Values from the prototype's control photos (docs/adr/0003).
const _sauce = NutritionLabel(
  servingSize: '2 Tbsp (31g)',
  servingGrams: 31,
  servingsPerContainer: 24,
  amounts: {
    LabelNutrient.energyKcal: 160,
    LabelNutrient.fat: 14,
    LabelNutrient.saturatedFat: 2.5,
    LabelNutrient.transFat: 0,
    LabelNutrient.cholesterol: 10,
    LabelNutrient.sodium: 190,
    LabelNutrient.carbohydrates: 7,
    LabelNutrient.fiber: 0,
    LabelNutrient.sugars: 7,
    LabelNutrient.addedSugars: 6,
    LabelNutrient.protein: 0,
  },
  dailyValuePercents: {
    LabelNutrient.fat: 18,
    LabelNutrient.saturatedFat: 11,
    LabelNutrient.cholesterol: 3,
    LabelNutrient.sodium: 8,
    LabelNutrient.carbohydrates: 2,
    LabelNutrient.fiber: 0,
    LabelNutrient.addedSugars: 13,
  },
);

void main() {
  group('nutritionLabelFromJson', () {
    test('reads amounts, %DV and the serving', () {
      final label = nutritionLabelFromJson({
        'servingSize': ' 2 Tbsp (31g) ',
        'servingGrams': 31,
        'servingsPerContainer': '24',
        'energyKcal': 160,
        'sodiumMg': 190,
        'sodiumMgDV': 8,
        'vitaminDMcg': '0',
      });
      expect(label.servingSize, '2 Tbsp (31g)');
      expect(label.servingGrams, 31);
      expect(label.servingsPerContainer, 24);
      expect(label.amounts[LabelNutrient.energyKcal], 160);
      expect(label.amounts[LabelNutrient.sodium], 190);
      expect(label.amounts[LabelNutrient.vitaminD], 0);
      expect(label.dailyValuePercents[LabelNutrient.sodium], 8);
      expect(label.isEmpty, isFalse);
    });

    test('drops values that are not plausible numbers', () {
      final label = nutritionLabelFromJson({
        'servingGrams': 0,
        'energyKcal': -5,
        'fat': 'lots',
        'protein': double.nan,
        // A %DV landing in the amount slot, a lost decimal point.
        'carbohydrates': 1200,
        'ironMg': 1.8,
        'calories': 160,
      });
      expect(label.servingGrams, isNull);
      expect(label.amounts, {LabelNutrient.iron: 1.8});
    });

    test('a thousands separator is not read as a decimal point', () {
      final label = nutritionLabelFromJson({
        'potassiumMg': '1,250',
        'energyKcal': '1,020.5',
        'fat': '1,5',
        'sodiumMg': '0,250',
      });
      expect(label.amounts[LabelNutrient.potassium], 1250);
      expect(label.amounts[LabelNutrient.energyKcal], 1020.5);
      expect(label.amounts[LabelNutrient.fat], 1.5);
      expect(label.amounts[LabelNutrient.sodium], 0.25);
    });

    test('an answer with nothing in it is empty, not a failure', () {
      expect(nutritionLabelFromJson(const {}).isEmpty, isTrue);
    });

    test('arguments that are not an object raise', () {
      expect(
        () => nutritionLabelFromJson(const ['fat', 14]),
        throwsA(isA<MealInterpreterException>()),
      );
    });

    test(
      'the schema offers every nutrient and a %DV only where one exists',
      () {
        final properties =
            nutritionLabelToolSchema['properties'] as Map<String, Object>;
        for (final n in LabelNutrient.values) {
          expect(properties, contains(n.wireName));
          expect(
            properties.containsKey(n.dailyValueWireName),
            n.dailyValue != null,
            reason: n.name,
          );
        }
      },
    );
  });

  group('checkNutritionLabel', () {
    test('a consistent label raises nothing', () {
      expect(checkNutritionLabel(_sauce), isEmpty);
    });

    test('an amount that disagrees with its own %DV is flagged', () {
      // The pasta label: thinking-on DeepSeek read 1.8 mg of iron as 1.0.
      final flags = checkNutritionLabel(
        const NutritionLabel(
          servingGrams: 56,
          amounts: {LabelNutrient.iron: 1.0},
          dailyValuePercents: {LabelNutrient.iron: 10},
        ),
      );
      expect(flags, hasLength(1));
      expect(flags.single.nutrient, LabelNutrient.iron);
      expect(flags.single.kind, LabelFlagKind.dailyValueMismatch);
      expect(flags.single.impliedAmount, closeTo(1.8, 1e-9));
    });

    test('added sugars is not checked against its %DV', () {
      // It has no field to show a mismatch on and is never stored.
      final flags = checkNutritionLabel(
        const NutritionLabel(
          servingGrams: 31,
          amounts: {LabelNutrient.addedSugars: 1},
          dailyValuePercents: {LabelNutrient.addedSugars: 50},
        ),
      );
      expect(flags, isEmpty);
    });

    test('a label that is wrong itself is flagged, not corrected', () {
      // The cheese label prints 6 g saturated fat at 25%, which is 5 g.
      const label = NutritionLabel(
        servingGrams: 28,
        amounts: {LabelNutrient.saturatedFat: 6},
        dailyValuePercents: {LabelNutrient.saturatedFat: 25},
      );
      expect(
        checkNutritionLabel(label).single.nutrient,
        LabelNutrient.saturatedFat,
      );
      expect(label.amounts[LabelNutrient.saturatedFat], 6);
    });

    test('calories far from the macros are flagged', () {
      final flags = checkNutritionLabel(
        const NutritionLabel(
          servingGrams: 31,
          amounts: {
            LabelNutrient.energyKcal: 610,
            LabelNutrient.fat: 14,
            LabelNutrient.carbohydrates: 7,
            LabelNutrient.protein: 0,
          },
        ),
      );
      expect(flags.single.kind, LabelFlagKind.energyMismatch);
      expect(flags.single.computedKcal, 154);
    });

    test('added sugars above sugars is flagged on the sugars field', () {
      final flags = checkNutritionLabel(
        const NutritionLabel(
          servingGrams: 31,
          amounts: {LabelNutrient.sugars: 1, LabelNutrient.addedSugars: 6},
        ),
      );
      expect(flags.single.kind, LabelFlagKind.partExceedsTotal);
      expect(flags.single.nutrient, LabelNutrient.sugars);
      expect(flags.single.part, LabelNutrient.addedSugars);
    });

    test('macros heavier than the serving are flagged on the serving', () {
      final flags = checkNutritionLabel(
        const NutritionLabel(
          servingGrams: 28,
          amounts: {
            LabelNutrient.fat: 12,
            LabelNutrient.carbohydrates: 130,
            LabelNutrient.protein: 2,
          },
        ),
      );
      expect(
        flags.map((f) => f.kind),
        contains(LabelFlagKind.macrosExceedServing),
      );
      expect(
        flags
            .firstWhere((f) => f.kind == LabelFlagKind.macrosExceedServing)
            .nutrient,
        isNull,
      );
    });

    test('a missing serving weight is flagged', () {
      final flags = checkNutritionLabel(
        const NutritionLabel(amounts: {LabelNutrient.energyKcal: 200}),
      );
      expect(flags.single.kind, LabelFlagKind.servingWeightMissing);
    });
  });

  group('customFoodFromLabel', () {
    test('scales per-serving amounts to per 100 g', () {
      final food = customFoodFromLabel(_sauce, barcode: '070200790148');
      expect(food.source, MealSourceEntity.custom);
      expect(food.code, '070200790148');
      expect(food.name, isNull);
      expect(food.servingQuantity, 31);
      expect(food.servingUnit, 'g');
      expect(food.servingSize, '2 Tbsp (31g)');
      expect(food.mealQuantity, '744');
      expect(food.nutriments.energyKcal100, closeTo(516.13, 0.01));
      expect(food.nutriments.cholesterol100, closeTo(32.26, 0.01));
      expect(food.nutriments.transFat100, 0);
      // Never stored: the app has no added-sugars value.
      expect(food.nutriments.sugars100, closeTo(22.58, 0.01));
    });

    test('without a serving weight nothing is converted', () {
      final food = customFoodFromLabel(
        const NutritionLabel(amounts: {LabelNutrient.energyKcal: 200}),
      );
      expect(food.servingQuantity, isNull);
      expect(food.nutriments.energyKcal100, isNull);
      expect(food.code, isNotEmpty);
    });
  });
}
