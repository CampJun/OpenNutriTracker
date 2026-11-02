import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';

import '../../tool/build_staple_foods.dart';

/// A USDA FoodData Central record shaped like the JSON downloads: only the
/// fields the converter reads.
Map<String, dynamic> usdaFood({
  required int fdcId,
  required String name,
  String category = 'Vegetables and Vegetable Products',
  String dataType = 'SR Legacy',
  int? ndb,
  Map<String, double> nutrients = const {
    '208': 50,
    '203': 1,
    '204': 1,
    '205': 10,
  },
  List<Map<String, dynamic>> portions = const [],
}) => {
  'fdcId': fdcId,
  'description': name,
  'dataType': dataType,
  'ndbNumber': ?ndb,
  'foodCategory': {'description': category},
  'foodNutrients': [
    for (final e in nutrients.entries)
      {
        'nutrient': {'number': e.key},
        'amount': e.value,
      },
  ],
  'foodPortions': portions,
};

Map<String, dynamic> foundation({
  required int fdcId,
  required String name,
  String category = 'Vegetables and Vegetable Products',
  int? ndb,
  Map<String, double> nutrients = const {
    '958': 50,
    '203': 1,
    '204': 1,
    '205': 10,
  },
  List<Map<String, dynamic>> portions = const [],
}) => usdaFood(
  fdcId: fdcId,
  name: name,
  category: category,
  dataType: 'Foundation',
  ndb: ndb,
  nutrients: nutrients,
  portions: portions,
);

Map<String, dynamic> srPortion(
  String modifier,
  double grams, {
  num amount = 1,
}) => {
  'amount': amount,
  'modifier': modifier,
  'measureUnit': {'name': 'undetermined'},
  'gramWeight': grams,
  'sequenceNumber': 1,
};

Map<String, dynamic> foundationPortion(
  String unit,
  double grams, {
  String modifier = '',
  num amount = 1,
  int sequence = 1,
}) => {
  'amount': amount,
  'modifier': modifier,
  'measureUnit': {'name': unit},
  'gramWeight': grams,
  'sequenceNumber': sequence,
};

StapleFoodsResult build({
  List<Map<String, dynamic>> foundationFoods = const [],
  List<Map<String, dynamic>> srFoods = const [],
  String exclusions = '',
  String inclusions = '',
}) => buildStapleFoods(
  foundation: foundationFoods,
  srLegacy: srFoods,
  exclusions: Exclusions.parse(exclusions),
  inclusions: Exclusions.parse(inclusions),
);

List<String> keptNames(StapleFoodsResult r) => [for (final f in r.kept) f.name];

String? reasonFor(StapleFoodsResult r, int fdcId) =>
    r.dropped.where((d) => d.fdcId == fdcId).firstOrNull?.reason;

void main() {
  group('Staple Food rules', () {
    test('keeps an SR Legacy food the name says is raw or dry', () {
      final r = build(
        srFoods: [
          usdaFood(fdcId: 1, name: 'Broccoli, raw'),
          usdaFood(
            fdcId: 2,
            name: 'Lentils, dry',
            category: 'Legumes and Legume Products',
          ),
          usdaFood(
            fdcId: 3,
            name: 'Rice, white, short-grain, uncooked',
            category: 'Cereal Grains and Pasta',
          ),
        ],
      );
      expect(keptNames(r), [
        'Broccoli, raw',
        'Lentils, dry',
        'Rice, white, short-grain, uncooked',
      ]);
    });

    test('drops an SR Legacy food whose name does not say as purchased', () {
      final r = build(
        srFoods: [usdaFood(fdcId: 1, name: 'Honey', category: 'Sweets')],
      );
      expect(r.kept, isEmpty);
      expect(reasonFor(r, 1), 'not as purchased');
    });

    test('keeps an as-purchased category without the word raw', () {
      final r = build(
        srFoods: [
          usdaFood(
            fdcId: 1,
            name: 'Oil, olive, salad or cooking',
            category: 'Fats and Oils',
          ),
          usdaFood(
            fdcId: 2,
            name: 'Cheese, cheddar',
            category: 'Dairy and Egg Products',
          ),
        ],
      );
      expect(r.kept, hasLength(2));
    });

    test('a Foundation food needs no as-purchased word', () {
      final r = build(
        foundationFoods: [foundation(fdcId: 1, name: 'Spinach, baby')],
      );
      expect(keptNames(r), ['Spinach, baby']);
    });

    test('drops cooked, canned and prepared foods', () {
      final r = build(
        srFoods: [
          usdaFood(fdcId: 1, name: 'Broccoli, cooked, boiled, drained'),
          usdaFood(fdcId: 2, name: 'Beans, snap, canned, raw'),
          usdaFood(fdcId: 3, name: 'Chicken breast tenders, breaded, uncooked'),
          usdaFood(fdcId: 4, name: 'Pancakes, plain, dry mix'),
        ],
      );
      expect(r.kept, isEmpty);
      for (final id in [1, 2, 3, 4]) {
        expect(reasonFor(r, id), 'cooked or prepared', reason: 'id $id');
      }
    });

    test('"unprepared" is not "prepared"', () {
      final r = build(
        srFoods: [usdaFood(fdcId: 1, name: 'Peas, green, frozen, unprepared')],
      );
      expect(r.kept, hasLength(1));
    });

    test('"mixed species" is not a mix', () {
      final r = build(
        srFoods: [usdaFood(fdcId: 1, name: 'Fish, trout, mixed species, raw')],
      );
      expect(r.kept, hasLength(1));
    });

    test('drops the four prepared-food categories', () {
      final r = build(
        srFoods: [
          for (final (i, c) in droppedCategories.indexed)
            usdaFood(fdcId: i, name: 'Something, raw', category: c),
        ],
      );
      expect(r.kept, isEmpty);
    });

    test('drops brand names written in capitals', () {
      final r = build(
        srFoods: [
          usdaFood(
            fdcId: 1,
            name: 'Cereals ready-to-eat, POST, Shredded Wheat, dry',
          ),
          usdaFood(fdcId: 2, name: 'HORMEL Canadian Style Bacon, raw'),
        ],
      );
      expect(r.kept, isEmpty);
      expect(reasonFor(r, 1), 'brand name');
    });

    test("USDA's own program note is not a brand", () {
      final r = build(
        srFoods: [
          usdaFood(
            fdcId: 1,
            name:
                "Apples, raw, with skin (Includes foods for USDA's Food Distribution Program)",
          ),
          usdaFood(fdcId: 2, name: 'Beans, pinto, NFS, raw'),
        ],
      );
      expect(r.kept, hasLength(2));
    });

    test('drops a food with no energy value', () {
      final r = build(
        foundationFoods: [
          foundation(
            fdcId: 1,
            name: 'Salt, table, iodized',
            nutrients: const {'307': 38000},
          ),
        ],
      );
      expect(r.kept, isEmpty);
      expect(reasonFor(r, 1), 'no kcal');
    });
  });

  group('Foundation Foods win', () {
    test('drops the SR Legacy record of a food Foundation keeps', () {
      final r = build(
        foundationFoods: [
          foundation(fdcId: 10, name: 'Broccoli, raw', ndb: 11090),
        ],
        srFoods: [usdaFood(fdcId: 20, name: 'Broccoli, raw', ndb: 11090)],
      );
      expect(r.kept.single.fdcId, 10);
      expect(r.kept.single.source, StapleFoodDTO.foundationSource);
      expect(reasonFor(r, 20), 'in Foundation Foods');
    });

    test('SR Legacy fills in when the Foundation record is not kept', () {
      final r = build(
        foundationFoods: [
          foundation(
            fdcId: 10,
            name: 'Beans, Dry, Red (0% moisture)',
            ndb: 16000,
            nutrients: const {'203': 20},
          ),
        ],
        srFoods: [
          usdaFood(
            fdcId: 20,
            name: 'Beans, red, mature seeds, raw',
            ndb: 16000,
          ),
        ],
      );
      expect(r.kept.single.fdcId, 20);
      expect(r.kept.single.source, StapleFoodDTO.srLegacySource);
    });
  });

  group('kcal', () {
    double kcalOf(Map<String, double> nutrients) => build(
      foundationFoods: [
        foundation(fdcId: 1, name: 'Peanuts, raw', nutrients: nutrients),
      ],
    ).kept.single.nutrients.energyKcal;

    test('prefers Energy (208)', () {
      expect(kcalOf({'208': 567, '958': 551, '957': 588}), 567);
    });

    test('then Atwater Specific Factors (958)', () {
      expect(kcalOf({'958': 551, '957': 588}), 551);
    });

    test('then Atwater General Factors (957)', () {
      expect(kcalOf({'957': 588}), 588);
    });
  });

  group('nutrients', () {
    test('maps USDA nutrient numbers to the app fields, per 100 g', () {
      final n = build(
        srFoods: [
          usdaFood(
            fdcId: 1,
            name: 'Spinach, raw',
            nutrients: const {
              '208': 23,
              '203': 2.86,
              '204': 0.39,
              '205': 3.63,
              '269': 0.42,
              '291': 2.2,
              '606': 0.063,
              '307': 79,
              '306': 558,
              '401': 28.1,
              '320': 469,
              '328': 0,
              '418': 0,
            },
          ),
        ],
      ).kept.single.nutrients;
      expect(n.energyKcal, 23);
      expect(n.proteins, 2.86);
      expect(n.fat, 0.39);
      expect(n.carbohydrates, 3.63);
      expect(n.sugars, 0.42);
      expect(n.fiber, 2.2);
      expect(n.saturatedFat, 0.063);
      expect(n.sodium, 79);
      expect(n.potassium, 558);
      expect(n.vitaminC, 28.1);
      expect(n.vitaminA, 469);
      expect(n.vitaminD, 0);
      expect(n.vitaminB12, 0);
      expect(n.cholesterol, isNull);
    });

    test("reads Foundation's total sugars number (269.3)", () {
      final n = build(
        foundationFoods: [
          foundation(
            fdcId: 1,
            name: 'Apples, gala, with skin, raw',
            nutrients: const {'958': 54, '269.3': 10.4},
          ),
        ],
      ).kept.single.nutrients;
      expect(n.sugars, 10.4);
    });

    test('rounds away float noise', () {
      final n = build(
        srFoods: [
          usdaFood(
            fdcId: 1,
            name: 'Celery, raw',
            nutrients: const {'208': 16, '204': 0.1 + 0.2},
          ),
        ],
      ).kept.single.nutrients;
      expect(n.fat, 0.3);
    });
  });

  group('Household Servings', () {
    List<StapleServingDTO> servingsOfFood(Map<String, dynamic> food) => build(
      foundationFoods: [if (food['dataType'] == 'Foundation') food],
      srFoods: [if (food['dataType'] != 'Foundation') food],
    ).kept.single.servings;

    test('labels an SR Legacy measure from its modifier', () {
      final s = servingsOfFood(
        usdaFood(
          fdcId: 1,
          name: 'Broccoli, raw',
          portions: [
            srPortion('cup, chopped', 91),
            srPortion('stalk', 151, amount: 0.5),
          ],
        ),
      );
      expect(s.map((e) => e.label), ['1 cup, chopped', '1 stalk']);
      expect(s.first.gramWeight, 91);
    });

    test('divides a fraction of a measure up to one', () {
      final s = servingsOfFood(
        usdaFood(
          fdcId: 1,
          name: 'Abiyuch, raw',
          category: 'Fruits and Fruit Juices',
          portions: [
            srPortion('cup', 114, amount: 0.5),
            srPortion('package (10 oz)', 94, amount: 0.33),
          ],
        ),
      );
      expect(s.map((e) => e.label), ['1 cup', '1 package (10 oz)']);
      // 0.33 is USDA's third: three of them, not 3.03.
      expect(s.map((e) => e.gramWeight), [228, 282]);
    });

    test('divides several of a measure down to one, in the singular', () {
      final s = servingsOfFood(
        usdaFood(
          fdcId: 1,
          name: 'Asparagus, raw',
          portions: [
            srPortion('spears', 58, amount: 4),
            srPortion('leaves', 2.5, amount: 5),
            srPortion('tomatoes', 300, amount: 2),
            srPortion('slices (6 per 6-oz pkg.)', 57, amount: 2),
            srPortion('tbsp', 10, amount: 2),
            srPortion('pea pods', 34, amount: 10),
          ],
        ),
      );
      expect(s.map((e) => e.label), [
        '1 spear',
        '1 leaf',
        '1 tomato',
        '1 slice (6 per 6-oz pkg.)',
        '1 tbsp',
        '1 pea pod',
      ]);
      expect(s.map((e) => e.gramWeight), [14.5, 0.5, 150, 28.5, 5, 3.4]);
    });

    test('keeps a weight its own label says is one of the measure', () {
      // USDA's "5 package (5 oz)" at 142 g: 142 g is 5 oz, one package.
      final s = servingsOfFood(
        usdaFood(
          fdcId: 1,
          name: 'Spinach, frozen, unprepared',
          portions: [srPortion('package (5 oz)', 142, amount: 5)],
        ),
      );
      expect(s.single.label, '1 package (5 oz)');
      expect(s.single.gramWeight, 142);
    });

    test('labels a Foundation measure from its unit and modifier', () {
      final s = servingsOfFood(
        foundation(
          fdcId: 1,
          name: 'Egg, white, dried',
          portions: [
            foundationPortion('cup', 107, modifier: 'sifted', sequence: 2),
            foundationPortion('tablespoon', 7, sequence: 1),
          ],
        ),
      );
      expect(s.map((e) => e.label), ['1 tablespoon', '1 cup, sifted']);
    });

    test('drops RACC, plain servings, weights and cooked yields', () {
      final s = servingsOfFood(
        usdaFood(
          fdcId: 1,
          name: 'Beef, ground, raw',
          category: 'Beef Products',
          portions: [
            foundationPortion('RACC', 85),
            srPortion('serving', 57),
            srPortion('oz', 28.35),
            srPortion('lb', 453.6),
            srPortion(
              'piece, cooked, excluding refuse (yield from 1 lb raw meat with refuse)',
              300,
            ),
            srPortion('NLEA serving', 85),
            srPortion('serving (3 oz)', 85),
            srPortion('oz, boneless', 28.35),
            srPortion('patty (4 per lb)', 113),
            srPortion('package (2 lb)', 907),
          ],
        ),
      );
      expect(s.map((e) => e.label), ['1 patty (4 per lb)', '1 package (2 lb)']);
    });

    test('keeps fluid ounces, which are a volume', () {
      final s = servingsOfFood(
        usdaFood(
          fdcId: 1,
          name: 'Milk, whole',
          category: 'Dairy and Egg Products',
          portions: [srPortion('fl oz', 30.5)],
        ),
      );
      expect(s.single.label, '1 fl oz');
    });

    test('drops a measure with no gram weight', () {
      final s = servingsOfFood(
        usdaFood(fdcId: 1, name: 'Kale, raw', portions: [srPortion('cup', 0)]),
      );
      expect(s, isEmpty);
    });
  });

  group('exclusions.txt', () {
    test('excludes by FDC id, category, prefix and contained text', () {
      final r = build(
        srFoods: [
          usdaFood(fdcId: 1, name: 'Kale, raw'),
          usdaFood(
            fdcId: 2,
            name: 'Beef, variety meats and by-products, lungs, raw',
            category: 'Beef Products',
          ),
          usdaFood(
            fdcId: 3,
            name: 'Shortening, household, raw',
            category: 'Fats and Oils',
          ),
          usdaFood(
            fdcId: 4,
            name: 'Cookies, raw dough',
            category: 'Baked Products',
          ),
          usdaFood(
            fdcId: 5,
            name: 'Breadfruit, raw',
            category: 'Fruits and Fruit Juices',
          ),
        ],
        exclusions: '''
# a comment
1   # kale
variety meats   # organs
^shortening
category: Baked Products
''',
      );
      expect(keptNames(r), ['Breadfruit, raw']);
      expect(reasonFor(r, 1), 'excluded: 1');
      expect(reasonFor(r, 2), 'excluded: variety meats');
      expect(reasonFor(r, 3), 'excluded: ^shortening');
      expect(reasonFor(r, 4), 'excluded: category: baked products');
    });

    test('reports rules that matched nothing', () {
      final exclusions = Exclusions.parse('kale\nwalrus\n999\n');
      final r = buildStapleFoods(
        foundation: const [],
        srLegacy: [usdaFood(fdcId: 1, name: 'Kale, raw')],
        exclusions: exclusions,
      );
      expect(exclusions.unusedRules(r), ['999', 'walrus']);
    });
  });

  group('inclusions.txt', () {
    test('rescues a staple the name rules reject', () {
      final r = build(
        srFoods: [
          usdaFood(fdcId: 1, name: 'Honey', category: 'Sweets'),
          usdaFood(
            fdcId: 2,
            name: 'Tofu, firm, prepared with calcium sulfate',
            category: 'Legumes and Legume Products',
          ),
        ],
        inclusions: '^honey\n^tofu, firm',
      );
      expect(keptNames(r), [
        'Honey',
        'Tofu, firm, prepared with calcium sulfate',
      ]);
    });

    test('does not override brands, categories or exclusions', () {
      final r = build(
        srFoods: [
          usdaFood(fdcId: 1, name: 'Honey, KRAFT', category: 'Sweets'),
          usdaFood(fdcId: 2, name: 'Honey bun', category: 'Fast Foods'),
          usdaFood(fdcId: 3, name: 'Honey, creamed', category: 'Sweets'),
        ],
        inclusions: '^honey',
        exclusions: 'creamed',
      );
      expect(r.kept, isEmpty);
    });
  });

  test('the asset round-trips through StapleFoodDTO', () {
    final kept = build(
      srFoods: [
        usdaFood(
          fdcId: 7,
          name: 'Kale, raw',
          portions: [srPortion('cup, chopped', 21)],
        ),
      ],
    ).kept.single;
    final back = StapleFoodDTO.fromJson(kept.toJson());
    expect(back.fdcId, 7);
    expect(back.name, 'Kale, raw');
    expect(back.source, StapleFoodDTO.srLegacySource);
    expect(back.nutrients.energyKcal, 50);
    expect(back.nutrients.proteins, 1);
    expect(back.servings.single.label, '1 cup, chopped');
    expect(back.servings.single.gramWeight, 21);
  });

  test('releaseOf reads the date from a USDA file name', () {
    expect(
      releaseOf('/x/FoodData_Central_foundation_food_json_2026-10-29.json'),
      '2026-10-29',
    );
    expect(
      releaseOf('FoodData_Central_sr_legacy_food_json_2018-04.json'),
      '2018-04',
    );
    expect(releaseOf('foods.json'), 'unknown');
  });
}
