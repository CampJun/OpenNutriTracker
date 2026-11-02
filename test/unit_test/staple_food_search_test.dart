import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/off_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/sp_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/staple_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';
import 'package:opennutritracker/features/add_meal/data/food_catalogue.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';

/// Fails the test if any network source is touched.
class _NoNetworkOff implements OFFDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('Open Food Facts was called: ${invocation.memberName}');
}

class _NoNetworkSupabase implements SpFoodDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      fail('Supabase was called: ${invocation.memberName}');
}

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  List<IntakeEntity> recent = const [];

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => recent;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeCustomMeals implements CustomMealDataSource {
  final List<MealDBO> meals = [];

  @override
  List<MealDBO> getAllCustomMeals() => meals;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeRecipes implements RecipeDataSource {
  @override
  List<RecipeDBO> getAllRecipes() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeCache implements RemoteSearchCacheDataSource {
  final List<MealDBO> meals = [];
  int writes = 0;

  @override
  List<MealDBO> getAllByMostRecentlyTouched() => meals;

  @override
  Future<void> cacheFromSearch(Iterable<MealDBO> incoming) async => writes++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

StapleFoodDataSource _staples(List<String> names) => StapleFoodDataSource(
  loadAsset: () async => jsonEncode({
    'foods': [
      for (final (i, name) in names.indexed)
        StapleFoodDTO(
          fdcId: 1000 + i,
          source: StapleFoodDTO.srLegacySource,
          name: name,
          category: 'Test',
          nutrients: const StapleNutrientsDTO(
            energyKcal: 52,
            proteins: 0.3,
            fat: 0.2,
            carbohydrates: 14,
          ),
        ).toJson(),
    ],
  }),
);

MealEntity _meal(String name, MealSourceEntity source, {String? code}) =>
    MealEntity(
      code: code ?? name,
      name: name,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: const MealNutrimentsEntity(
        energyKcal100: 50,
        carbohydrates100: 10,
        fat100: 1,
        proteins100: 1,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: source,
    );

void main() {
  setUp(FoodCatalogue.resetForTesting);
  tearDown(() => FoodCatalogue.setForTesting(network: true, scanner: true));

  group('ProductsRepository with the network sources off', () {
    final repository = ProductsRepository(
      _NoNetworkOff(),
      _NoNetworkSupabase(),
      _staples(['Apples, fuji, with skin, raw', 'Bananas, raw']),
    );

    test('finds Staple Foods', () async {
      final meals = await repository.getStapleFoodsByString('apple');
      expect(meals.single.name, 'Apples, fuji, with skin, raw');
      expect(meals.single.code, 'fdc:1000');
      expect(meals.single.source, MealSourceEntity.fdc);
    });

    test('never calls Open Food Facts or Supabase', () async {
      expect(await repository.getOFFProductsByString('apple'), isEmpty);
      expect(await repository.getSupabaseFoodsByString('apple'), isEmpty);
      await expectLater(
        repository.getOFFProductByBarcode('4000417025005'),
        throwsA(isA<ProductNotFoundException>()),
      );
    });
  });

  group('SearchProductsUseCase.searchFDCFoodByString', () {
    late _FakeCustomMeals custom;
    late _FakeCache cache;
    late SearchProductsUseCase useCase;

    setUp(() {
      custom = _FakeCustomMeals();
      cache = _FakeCache();
      useCase = SearchProductsUseCase(
        ProductsRepository(
          _NoNetworkOff(),
          _NoNetworkSupabase(),
          _staples([
            'Apples, fuji, with skin, raw',
            'Apples, gala, with skin, raw',
          ]),
        ),
        _FakeGetIntakeUsecase(),
        custom,
        cache,
        _FakeRecipes(),
        _FakeGetConfigUsecase(),
      );
    });

    test("searches Staple Foods, the user's own foods first", () async {
      custom.meals.add(
        MealDBO.fromMealEntity(
          _meal('Apple pie (mine)', MealSourceEntity.custom),
        ),
      );
      final result = await useCase.searchFDCFoodByString('apple');
      expect(result.meals.map((m) => m.name), [
        'Apple pie (mine)',
        'Apples, fuji, with skin, raw',
        'Apples, gala, with skin, raw',
      ]);
      expect(result.remoteSourceFailed, isFalse);
    });

    test('runs even for the short queries that skip the network', () async {
      final result = await useCase.searchFDCFoodByString(
        'apple',
        skipRemote: true,
      );
      expect(result.meals, hasLength(2));
    });

    test('writes nothing to the search cache', () async {
      await useCase.searchFDCFoodByString('apple');
      expect(cache.writes, 0);
    });

    test('leaves out old Supabase results left in the cache', () async {
      cache.meals.add(
        MealDBO.fromMealEntity(
          _meal(
            'Apple pie, commercially prepared',
            MealSourceEntity.fdc,
            code: '170',
          ),
        ),
      );
      final result = await useCase.searchFDCFoodByString('apple');
      expect(
        result.meals.map((m) => m.name),
        isNot(contains('Apple pie, commercially prepared')),
      );
    });
  });
}
