import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';

/// The custom-food form keeps every nutrient the app stores (docs/adr/0003).
///
/// It used to build the saved nutrients from the fourteen it showed, so
/// cholesterol, trans fat and eight more were dropped on every save; and a
/// blanked Advanced field fell back to the stored per-100 value multiplied
/// by the scale factor.
class _Fake
    implements
        GetConfigUsecase,
        CustomMealDataSource,
        ConfigRepository,
        FavouriteMealRepository,
        IntakeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late EditMealBloc bloc;
  setUp(() => bloc = EditMealBloc(_Fake(), _Fake(), _Fake(), _Fake(), _Fake()));
  tearDown(() => bloc.close());

  const stored = MealEntity(
    code: 'id',
    name: 'Sauce',
    url: null,
    mealQuantity: '744',
    mealUnit: 'g',
    servingQuantity: 31,
    servingUnit: 'g',
    servingSize: '2 Tbsp (31g)',
    nutriments: MealNutrimentsEntity(
      energyKcal100: 516,
      carbohydrates100: 22.6,
      fat100: 45.2,
      proteins100: 0,
      sugars100: 22.6,
      saturatedFat100: 8.1,
      fiber100: 0,
      cholesterol100: 32.3,
      transFat100: 0,
      vitaminC100: 9,
      zinc100: 1.2,
    ),
    source: MealSourceEntity.custom,
  );

  MealEntity save(
    String base, {
    String? cholesterol,
    String? transFat,
    String? vitaminC,
  }) => bloc.createNewMealEntity(
    stored,
    'Sauce',
    '',
    '744',
    '31',
    base,
    'g',
    '160',
    '7',
    '14',
    '0',
    cholesterolText: cholesterol,
    transFatText: transFat,
    vitaminCText: vitaminC,
  );

  test('a field the form did not show keeps its stored value, unscaled', () {
    final meal = save('31');
    expect(meal.nutriments.cholesterol100, 32.3);
    expect(meal.nutriments.zinc100, 1.2);
  });

  test('a shown field is typed per base quantity and scaled', () {
    final meal = save('31', cholesterol: '10', transFat: '0');
    expect(meal.nutriments.cholesterol100, closeTo(32.26, 0.01));
    expect(meal.nutriments.transFat100, 0);
  });

  test('a blanked field is saved empty, not as a scaled old value', () {
    final meal = save('31', vitaminC: '');
    expect(meal.nutriments.vitaminC100, isNull);
  });
}
