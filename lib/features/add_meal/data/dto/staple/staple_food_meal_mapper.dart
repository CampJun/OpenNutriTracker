import 'package:opennutritracker/core/utils/web_url.dart';
import 'package:opennutritracker/features/add_meal/data/dto/fdc/fdc_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_portion_entity.dart';

/// Prefix of a Staple Food's [MealEntity.code]: `fdc:171077`.
///
/// Staple Foods keep the persisted `MealSourceEntity.fdc` tag (no Hive
/// migration; docs/adr/0002), which old Supabase results carry too — with
/// the backend's own row id as their code. The prefix keeps a Staple Food
/// from ever being mistaken for one of those.
const stapleFoodCodePrefix = 'fdc:';

bool isStapleFoodCode(String? code) =>
    code != null && code.startsWith(stapleFoodCodePrefix);

extension StapleFoodMeal on StapleFoodDTO {
  /// This Staple Food as a meal the app can show, weigh and log.
  ///
  /// Grams are the default: there is no serving quantity, so the meal detail
  /// opens on grams. The Household Servings become [MealEntity.portions],
  /// which the unit picker offers and which scale by their own weight.
  MealEntity toMealEntity() => MealEntity(
    code: '$stapleFoodCodePrefix$fdcId',
    name: name,
    url: normalizeWebUrl(FDCConst.getFoodDetailUrlString('$fdcId')),
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: nutrients.energyKcal,
      carbohydrates100: nutrients.carbohydrates,
      fat100: nutrients.fat,
      proteins100: nutrients.proteins,
      sugars100: nutrients.sugars,
      saturatedFat100: nutrients.saturatedFat,
      fiber100: nutrients.fiber,
      monounsaturatedFat100: nutrients.monounsaturatedFat,
      polyunsaturatedFat100: nutrients.polyunsaturatedFat,
      transFat100: nutrients.transFat,
      cholesterol100: nutrients.cholesterol,
      sodium100: nutrients.sodium,
      potassium100: nutrients.potassium,
      magnesium100: nutrients.magnesium,
      calcium100: nutrients.calcium,
      iron100: nutrients.iron,
      zinc100: nutrients.zinc,
      phosphorus100: nutrients.phosphorus,
      vitaminA100: nutrients.vitaminA,
      vitaminC100: nutrients.vitaminC,
      vitaminD100: nutrients.vitaminD,
      vitaminB6100: nutrients.vitaminB6,
      vitaminB12100: nutrients.vitaminB12,
      niacin100: nutrients.niacin,
    ),
    source: MealSourceEntity.fdc,
    backendSource: source,
    portions: [
      for (final serving in servings)
        MealPortionEntity(
          label: serving.label,
          englishLabel: serving.label,
          gramWeight: serving.gramWeight,
          // USDA's measures are English; the label helpers decide whether
          // that can be shown as-is in the reader's language.
          localized: false,
        ),
    ],
    detailed: true,
  );
}
