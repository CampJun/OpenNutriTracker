import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/staple_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_meal_mapper.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/util/meal_quantity_converter.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';

StapleFoodDTO food(
  int id,
  String name, {
  String source = StapleFoodDTO.srLegacySource,
  double kcal = 100,
  List<StapleServingDTO> servings = const [],
}) => StapleFoodDTO(
  fdcId: id,
  source: source,
  name: name,
  category: 'Test',
  nutrients: StapleNutrientsDTO(
    energyKcal: kcal,
    proteins: 10,
    fat: 5,
    carbohydrates: 1,
  ),
  servings: servings,
);

StapleFoodDataSource sourceOf(List<StapleFoodDTO> foods) =>
    StapleFoodDataSource(
      loadAsset: () async => jsonEncode({
        'foundationRelease': 'test',
        'srLegacyRelease': 'test',
        'foods': [for (final f in foods) f.toJson()],
      }),
    );

Future<List<String>> namesFor(
  StapleFoodDataSource source,
  String query,
) async => [for (final f in await source.search(query)) f.name];

void main() {
  group('StapleFoodDataSource.search', () {
    final source = sourceOf([
      food(1, 'Chicken, broilers or fryers, breast, meat and skin, raw'),
      food(
        2,
        'Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw',
      ),
      food(3, 'Chicken, broilers or fryers, wing, meat and skin, raw'),
      food(4, 'Flour, rice, white, unenriched'),
      food(5, 'Rice, white, long grain, unenriched, raw'),
      food(6, 'Pineapple, raw'),
      food(7, 'Apples, fuji, with skin, raw'),
      food(
        8,
        'Eggs, Grade A, Large, egg whole',
        source: StapleFoodDTO.foundationSource,
      ),
    ]);

    test('matches words in any order', () async {
      expect(
        (await namesFor(source, 'raw breast chicken')).first,
        contains('breast'),
      );
      expect(
        (await namesFor(source, 'chicken breast raw')).first,
        contains('breast'),
      );
    });

    test('a named qualifier lifts the foods that have it', () async {
      final names = await namesFor(source, 'chicken wing');
      expect(
        names.first,
        'Chicken, broilers or fryers, wing, meat and skin, raw',
      );
    });

    test(
      'a food titled by the query beats one that only mentions it',
      () async {
        final names = await namesFor(source, 'rice');
        expect(names.first, 'Rice, white, long grain, unenriched, raw');
        expect(names, contains('Flour, rice, white, unenriched'));
      },
    );

    test('matches a plural by prefix', () async {
      expect(await namesFor(source, 'apple'), ['Apples, fuji, with skin, raw']);
      expect(await namesFor(source, 'egg'), [
        'Eggs, Grade A, Large, egg whole',
      ]);
    });

    test('does not match a different word that ends the same', () async {
      expect(
        await namesFor(source, 'apple'),
        isNot(contains('Pineapple, raw')),
      );
    });

    test("USDA's distribution note does not sink the plain food", () async {
      final pinto = sourceOf([
        food(1, 'Beans, pinto, immature seeds, frozen, unprepared'),
        food(2, 'Beans, pinto, mature seeds, sprouted, raw'),
        food(
          3,
          "Beans, pinto, mature seeds, raw (Includes foods for USDA's Food Distribution Program)",
        ),
        food(4, 'Beans, cannellini, dry'),
      ]);
      expect(
        (await namesFor(pinto, 'pinto beans')).first,
        startsWith('Beans, pinto, mature seeds, raw'),
      );
      // Each misses one word; the one that has the bean the user named wins.
      expect(
        (await namesFor(pinto, 'dry pinto beans')).first,
        startsWith('Beans, pinto, mature seeds, raw'),
      );
    });

    test('an empty query finds nothing', () async {
      expect(await source.search('  '), isEmpty);
    });

    test('caps the result count', () async {
      final many = sourceOf([
        for (var i = 0; i < StapleFoodDataSource.maxResults + 10; i++)
          food(i, 'Beef, cut $i, raw'),
      ]);
      expect(
        await many.search('beef'),
        hasLength(StapleFoodDataSource.maxResults),
      );
    });

    test('reads the asset once', () async {
      var reads = 0;
      final counted = StapleFoodDataSource(
        loadAsset: () async {
          reads++;
          return jsonEncode({
            'foods': [food(1, 'Kale, raw').toJson()],
          });
        },
      );
      await counted.search('kale');
      await counted.search('kale');
      expect(reads, 1);
    });
  });

  group('Staple Food as a meal', () {
    final meal = food(
      171705,
      'Broccoli, raw',
      kcal: 34,
      servings: const [
        StapleServingDTO(label: '1 cup, chopped', gramWeight: 91),
        StapleServingDTO(label: '1 stalk', gramWeight: 151),
      ],
    ).toMealEntity();

    test('keeps the fdc tag with a prefixed FDC id and the dataset', () {
      expect(meal.source, MealSourceEntity.fdc);
      expect(meal.code, 'fdc:171705');
      expect(isStapleFoodCode(meal.code), isTrue);
      expect(isStapleFoodCode('171705'), isFalse);
      expect(meal.backendSource, StapleFoodDTO.srLegacySource);
      expect(meal.url, contains('171705'));
    });

    test('defaults to grams: no serving quantity, unit g', () {
      expect(meal.servingQuantity, isNull);
      expect(meal.scalableServingQuantity, isNull);
      expect(meal.mealUnit, 'g');
      expect(meal.isSolid, isTrue);
    });

    test('carries nutrients per 100 g', () {
      expect(meal.nutriments.energyKcal100, 34);
      expect(meal.nutriments.energyPerUnit, closeTo(0.34, 1e-9));
    });

    test('Household Servings scale by their own weight', () {
      expect(meal.portions.map((p) => p.label), ['1 cup, chopped', '1 stalk']);
      expect(convertQuantityToBaseUnit(2, portionUnit(0), meal), 182);
      expect(convertQuantityToBaseUnit(1, portionUnit(1), meal), 151);
      expect(convertQuantityToBaseUnit(137, 'g', meal), 137);
    });
  });

  group('the committed asset', () {
    late StapleFoodDataSource source;
    late List<StapleFoodDTO> all;

    setUpAll(() async {
      final text = File(StapleFoodDataSource.assetPath).readAsStringSync();
      source = StapleFoodDataSource(loadAsset: () async => text);
      all = await source.allFoods();
    });

    test('parses, and every food has kcal and a USDA source', () {
      expect(all.length, greaterThan(1000));
      for (final f in all) {
        expect(f.nutrients.energyKcal, isNonNegative, reason: f.name);
        expect(
          [StapleFoodDTO.foundationSource, StapleFoodDTO.srLegacySource],
          contains(f.source),
          reason: f.name,
        );
        for (final s in f.servings) {
          expect(s.gramWeight, greaterThan(0), reason: '${f.name}: ${s.label}');
        }
      }
    });

    test('FDC ids are unique', () {
      expect(all.map((f) => f.fdcId).toSet(), hasLength(all.length));
    });

    test('everyday staples are found first', () async {
      Future<String> top(String q) async => (await source.search(q)).first.name;
      expect(
        await top('chicken breast raw'),
        allOf(contains('Chicken'), contains('breast'), contains('raw')),
      );
      expect(await top('banana'), startsWith('Bananas'));
      expect(await top('rice'), startsWith('Rice'));
      expect(await top('olive oil'), 'Oil, olive, salad or cooking');
      expect(await top('rolled oats'), startsWith('Oats'));
      expect(await top('ground beef 90%'), contains('90% lean'));
    });

    test('nothing cooked, canned or branded slipped through', () {
      final bad = RegExp(
        r'\b(cooked|canned|fried|roasted|baked|boiled)\b',
        caseSensitive: false,
      );
      expect(
        all.where((f) => bad.hasMatch(f.name)).map((f) => f.name),
        isEmpty,
      );
    });
  });
}
