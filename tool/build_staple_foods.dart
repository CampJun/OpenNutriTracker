// Builds assets/staple_foods.json from the USDA FoodData Central downloads.
//
//   dart run tool/build_staple_foods.dart <foundation.json> <sr_legacy.json>
//
// or `just staple_foods <foundation.json> <sr_legacy.json>`. Both inputs are
// the JSON downloads from https://fdc.nal.usda.gov/download-datasets
// ("Foundation Foods" and "SR Legacy"); they are ~220 MB unzipped together
// and are not committed. The asset records the release each came from.
//
// What a Staple Food is, and why the set is built this way, is in CONTEXT.md
// and docs/adr/0002. In short:
//
//  * A food qualifies when it is as purchased, before cooking (the name says
//    raw, dry, uncooked, unprepared... or its category is one whose foods
//    are bought ready to weigh, like dairy or oils) and nothing in its name
//    says cooked, canned or prepared. Brand-name items and four categories
//    of prepared food are dropped.
//  * tool/staple_foods/inclusions.txt rescues staples whose names fail the
//    name rules ("Honey"); every line of tool/staple_foods/exclusions.txt
//    then removes a food by FDC id, category, or a piece of its name.
//  * Foundation Foods win: an SR Legacy record of the same food (same NDB
//    number) is dropped when the Foundation record is kept. Foundation
//    records without any energy value are not kept, so SR fills in for them.
//  * kcal is Energy (208), else Atwater Specific (958), else Atwater
//    General (957).
//  * Household Servings keep every USDA measure with a gram weight except
//    RACC, plain "serving", weight units (oz, lb, which grams already
//    cover) and cooked yields.
//
// A review report — every kept food per category, and every dropped food
// with the reason — is written to build/staple_foods_review/ (gitignored).
import 'dart:convert';
import 'dart:io';

import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';

const assetPath = 'assets/staple_foods.json';
const exclusionsPath = 'tool/staple_foods/exclusions.txt';
const inclusionsPath = 'tool/staple_foods/inclusions.txt';
const reviewDir = 'build/staple_foods_review';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/build_staple_foods.dart '
      '<foundation.json> <sr_legacy.json>',
    );
    exit(64);
  }
  final foundationFile = File(args[0]);
  final srFile = File(args[1]);
  final foundation = _foods(foundationFile, 'FoundationFoods');
  final sr = _foods(srFile, 'SRLegacyFoods');
  final exclusions = Exclusions.parse(File(exclusionsPath).readAsStringSync());
  final inclusions = Exclusions.parse(File(inclusionsPath).readAsStringSync());

  final result = buildStapleFoods(
    foundation: foundation,
    srLegacy: sr,
    exclusions: exclusions,
    inclusions: inclusions,
  );

  final asset = {
    'foundationRelease': releaseOf(foundationFile.path),
    'srLegacyRelease': releaseOf(srFile.path),
    'foods': [for (final f in result.kept) f.toJson()],
  };
  // One food per line: the committed file diffs food by food when the
  // curation changes.
  final buffer = StringBuffer()
    ..writeln('{')
    ..writeln('"foundationRelease": ${jsonEncode(asset['foundationRelease'])},')
    ..writeln('"srLegacyRelease": ${jsonEncode(asset['srLegacyRelease'])},')
    ..writeln('"foods": [');
  for (var i = 0; i < result.kept.length; i++) {
    buffer.write(jsonEncode(result.kept[i].toJson()));
    buffer.writeln(i == result.kept.length - 1 ? '' : ',');
  }
  buffer.writeln(']}');
  File(assetPath).writeAsStringSync(buffer.toString());

  _writeReview(result);
  final unused = exclusions.unusedRules(result);
  stdout.writeln(
    'Kept ${result.kept.length} Staple Foods '
    '(${result.kept.where((f) => f.source == StapleFoodDTO.foundationSource).length} '
    'Foundation, '
    '${result.kept.where((f) => f.source == StapleFoodDTO.srLegacySource).length} '
    'SR Legacy); dropped ${result.dropped.length}. '
    'Wrote $assetPath and $reviewDir/.',
  );
  for (final rule in unused) {
    stdout.writeln('warning: exclusion matched nothing: $rule');
  }
}

List<Map<String, dynamic>> _foods(File file, String key) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final foods = decoded[key];
  if (foods is! List) {
    stderr.writeln('${file.path}: no "$key" list — wrong file?');
    exit(65);
  }
  return foods.cast<Map<String, dynamic>>();
}

/// The release date in a USDA download's file name —
/// `FoodData_Central_foundation_food_json_2026-10-29.json` is `2026-10-29`.
String releaseOf(String path) =>
    RegExp(r'(\d{4}-\d{2}(?:-\d{2})?)').allMatches(path).lastOrNull?.group(1) ??
    'unknown';

// ---------------------------------------------------------------------------
// Rules

/// Categories whose foods are prepared dishes, never Staple Foods.
const droppedCategories = {
  'Fast Foods',
  'Restaurant Foods',
  'Baby Foods',
  'Meals, Entrees, and Side Dishes',
};

/// Categories whose foods are bought ready to weigh, so they qualify without
/// the name saying "raw" — milk, cheese, butter, oils, nuts, spices.
const asPurchasedCategories = {
  'Dairy and Egg Products',
  'Fats and Oils',
  'Nut and Seed Products',
  'Spices and Herbs',
};

/// A word in the name that says the food is as purchased, before cooking.
final asPurchasedWords = RegExp(
  r'\b(raw|dry|dried|uncooked|unprepared|unheated|flour|meal|bran|germ)\b',
  caseSensitive: false,
);

/// A word in the name that says the food was cooked, canned or prepared.
final preparedWords = RegExp(
  r'\b(cooked|boiled|roasted|fried|braised|baked|grilled|broiled|stewed|'
  r'prepared|canned|microwaved|steamed|scrambled|poached|simmered|heated|'
  r'smoked|breaded|battered|toasted|sauteed|blanched|rotisserie|stuffed|'
  r'reconstituted|ready-to-eat|ready-to-heat|mix)\b',
  caseSensitive: false,
);

/// All-caps words in USDA names that are not brands.
const _notBrands = {
  'USDA',
  "USDA'S",
  'NFS',
  'DHA',
  'ARA',
  'USA',
  'NLEA',
  'UHT',
};
final _capsWord = RegExp(r"\b[A-Z][A-Z0-9&'-]{2,}\b");

/// SR Legacy writes brand names in capitals — "Cereals ready-to-eat, POST,
/// HONEY BUNCHES OF OATS" — and generic foods never are.
bool looksBranded(String name) => _capsWord.allMatches(name).any((m) {
  final word = m.group(0)!.toUpperCase();
  return !_notBrands.contains(word) &&
      !_notBrands.contains(word.replaceFirst(RegExp(r"'$"), ''));
});

/// Why [food] is not a Staple Food by the rules, or null when it is.
///
/// Foundation Foods are sampled as ingredients and name the state only when
/// it is not the plain one — "Spinach, baby", "Halibut, frozen, wild
/// caught" — so they need no as-purchased word; SR Legacy writes "raw" on
/// every raw record and needs one. [included] — a match in
/// tool/staple_foods/inclusions.txt — overrides the two name rules, for
/// staples whose names read otherwise: "Honey", "Tofu, firm, prepared with
/// calcium sulfate".
String? ruleRejection(Map<String, dynamic> food, {bool included = false}) {
  final name = food['description'] as String? ?? '';
  final category = _category(food);
  final foundation = food['dataType'] == 'Foundation';
  if (droppedCategories.contains(category)) return 'category: $category';
  if (looksBranded(name)) return 'brand name';
  if (!included) {
    if (preparedWords.hasMatch(name)) return 'cooked or prepared';
    if (!foundation &&
        !asPurchasedWords.hasMatch(name) &&
        !asPurchasedCategories.contains(category)) {
      return 'not as purchased';
    }
  }
  if (energyKcal(food) == null) return 'no kcal';
  return null;
}

String _category(Map<String, dynamic> food) =>
    (food['foodCategory'] as Map?)?['description'] as String? ?? '';

// ---------------------------------------------------------------------------
// Exclusions

/// tool/staple_foods/exclusions.txt: one rule per line, `#` starts a
/// comment. A number excludes that FDC id; `category: Name` every food in
/// that category; `^Text` every food whose name starts with Text; anything
/// else every food whose name contains it. Matching ignores case.
class Exclusions {
  final Set<int> ids;
  final Set<String> categories;
  final List<String> prefixes;
  final List<String> patterns;

  Exclusions({
    required this.ids,
    this.categories = const {},
    this.prefixes = const [],
    required this.patterns,
  });

  factory Exclusions.parse(String text) {
    final ids = <int>{};
    final categories = <String>{};
    final prefixes = <String>[];
    final patterns = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      final id = int.tryParse(line);
      if (id != null) {
        ids.add(id);
      } else if (line.toLowerCase().startsWith('category:')) {
        categories.add(line.substring('category:'.length).trim().toLowerCase());
      } else if (line.startsWith('^')) {
        prefixes.add(line.substring(1).toLowerCase());
      } else {
        patterns.add(line.toLowerCase());
      }
    }
    return Exclusions(
      ids: ids,
      categories: categories,
      prefixes: prefixes,
      patterns: patterns,
    );
  }

  /// The rule that excludes a food, or null.
  String? match(int fdcId, String name, [String category = '']) {
    if (ids.contains(fdcId)) return '$fdcId';
    final lowerCategory = category.toLowerCase();
    if (categories.contains(lowerCategory)) return 'category: $lowerCategory';
    final lower = name.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) return '^$prefix';
    }
    for (final pattern in patterns) {
      if (lower.contains(pattern)) return pattern;
    }
    return null;
  }

  /// Rules that excluded nothing — usually a typo, or a food the rules
  /// already drop.
  List<String> unusedRules(StapleFoodsResult result) {
    const tag = 'excluded: ';
    final used = {
      for (final d in result.dropped)
        if (d.reason.startsWith(tag)) d.reason.substring(tag.length),
    };
    return [
      for (final id in ids) '$id',
      for (final c in categories) 'category: $c',
      for (final p in prefixes) '^$p',
      ...patterns,
    ].where((rule) => !used.contains(rule)).toList();
  }
}

// ---------------------------------------------------------------------------
// Build

class DroppedFood {
  final int fdcId;
  final String source;
  final String name;
  final String category;
  final String reason;

  DroppedFood(this.fdcId, this.source, this.name, this.category, this.reason);
}

class StapleFoodsResult {
  final List<StapleFoodDTO> kept;
  final List<DroppedFood> dropped;

  StapleFoodsResult(this.kept, this.dropped);
}

StapleFoodsResult buildStapleFoods({
  required List<Map<String, dynamic>> foundation,
  required List<Map<String, dynamic>> srLegacy,
  required Exclusions exclusions,
  Exclusions? inclusions,
}) {
  final rescue = inclusions ?? Exclusions(ids: const {}, patterns: const []);
  final kept = <StapleFoodDTO>[];
  final dropped = <DroppedFood>[];
  final keptNdbNumbers = <Object>{};

  void consider(Map<String, dynamic> food, String source) {
    final fdcId = (food['fdcId'] as num).toInt();
    final name = (food['description'] as String? ?? '').trim();
    final category = _category(food);
    void drop(String reason) =>
        dropped.add(DroppedFood(fdcId, source, name, category, reason));

    final ndb = food['ndbNumber'];
    if (source == StapleFoodDTO.srLegacySource &&
        ndb != null &&
        keptNdbNumbers.contains('$ndb')) {
      return drop('in Foundation Foods');
    }
    final rejection = ruleRejection(
      food,
      included: rescue.match(fdcId, name, category) != null,
    );
    if (rejection != null) return drop(rejection);
    final excluded = exclusions.match(fdcId, name, category);
    if (excluded != null) return drop('excluded: $excluded');

    if (ndb != null) keptNdbNumbers.add('$ndb');
    kept.add(
      StapleFoodDTO(
        fdcId: fdcId,
        source: source,
        name: name,
        category: category,
        nutrients: nutrientsOf(food),
        servings: servingsOf(food),
      ),
    );
  }

  for (final food in foundation) {
    consider(food, StapleFoodDTO.foundationSource);
  }
  for (final food in srLegacy) {
    consider(food, StapleFoodDTO.srLegacySource);
  }
  kept.sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.fdcId.compareTo(b.fdcId);
  });
  return StapleFoodsResult(kept, dropped);
}

// ---------------------------------------------------------------------------
// Nutrients

/// USDA nutrient numbers, keyed by what they become.
Map<String, double> _amounts(Map<String, dynamic> food) {
  final amounts = <String, double>{};
  for (final entry in (food['foodNutrients'] as List?) ?? const []) {
    final nutrient = (entry as Map)['nutrient'] as Map?;
    final number = nutrient?['number'] as String?;
    final amount = entry['amount'];
    if (number == null || amount is! num) continue;
    amounts[number] = amount.toDouble();
  }
  return amounts;
}

/// Energy (208), else Atwater Specific Factors (958), else Atwater General
/// Factors (957) — the most specific value USDA publishes for the food.
double? energyKcal(Map<String, dynamic> food) {
  final a = _amounts(food);
  return a['208'] ?? a['958'] ?? a['957'];
}

StapleNutrientsDTO nutrientsOf(Map<String, dynamic> food) {
  final a = _amounts(food);
  double? n(String number) => _round(a[number]);
  return StapleNutrientsDTO(
    energyKcal: _round(a['208'] ?? a['958'] ?? a['957'])!,
    carbohydrates: n('205'),
    fat: n('204'),
    proteins: n('203'),
    sugars: _round(a['269'] ?? a['269.3']),
    saturatedFat: n('606'),
    fiber: n('291'),
    monounsaturatedFat: n('645'),
    polyunsaturatedFat: n('646'),
    transFat: n('605'),
    cholesterol: n('601'),
    sodium: n('307'),
    potassium: n('306'),
    magnesium: n('304'),
    calcium: n('301'),
    iron: n('303'),
    zinc: n('309'),
    phosphorus: n('305'),
    vitaminA: n('320'),
    vitaminC: n('401'),
    vitaminD: n('328'),
    vitaminB6: n('415'),
    vitaminB12: n('418'),
    niacin: n('406'),
  );
}

/// Four significant figures at most — more than USDA measures, and it keeps
/// float noise like 0.30000000000000004 out of the asset.
double? _round(double? value) {
  if (value == null) return null;
  if (value == 0) return 0;
  return double.parse(value.toStringAsPrecision(4));
}

// ---------------------------------------------------------------------------
// Household Servings

/// Measures that are not something a person takes: label servings, and
/// weights that grams already cover.
const _notHouseholdMeasures = {
  'racc',
  'serving',
  'oz',
  'lb',
  'undetermined',
  'quantity not specified',
};

List<StapleServingDTO> servingsOf(Map<String, dynamic> food) {
  final portions =
      [
        for (final p in (food['foodPortions'] as List?) ?? const [])
          (p as Map).cast<String, dynamic>(),
      ]..sort(
        (a, b) => ((a['sequenceNumber'] as num?) ?? 0).compareTo(
          (b['sequenceNumber'] as num?) ?? 0,
        ),
      );
  final servings = <StapleServingDTO>[];
  final seen = <String>{};
  for (final p in portions) {
    final serving = householdServing(p);
    if (serving == null || !seen.add(serving.label)) continue;
    servings.add(serving);
  }
  return servings;
}

/// One of [portion]'s measure, or null when it is not a Household Serving.
///
/// USDA states some measures as several or a fraction — "0.5 cup" at
/// 114 g, "4 spears" at 58 g. The app counts a serving in ones and shows
/// its label without the count, so those would read "cup (114 g)" for half
/// a cup. Each is divided down to one: "1 cup" at 228 g, "1 spear" at
/// 14.5 g.
StapleServingDTO? householdServing(Map<String, dynamic> portion) {
  final grams = (portion['gramWeight'] as num?)?.toDouble();
  if (grams == null || grams <= 0) return null;
  final measure = servingMeasure(portion);
  if (measure == null) return null;
  final stated = _statedWeight(measure);
  // "5 package (5 oz)" at 142 g: the weight is already one package's.
  final amount = stated != null && (grams - stated).abs() <= stated * 0.1
      ? 1.0
      : _amountOf(portion);
  if (amount <= 0) return null;
  return StapleServingDTO(
    label: '1 ${amount > 1 ? singularMeasure(measure) : measure}',
    gramWeight: _round(grams / amount)!,
  );
}

/// The weight a measure states for one of itself — "package (10 oz)" —
/// in grams, or null when it states none.
double? _statedWeight(String measure) {
  final match = RegExp(
    r'\((\d+(?:\.\d+)?)\s*(oz|lb)\)',
  ).firstMatch(measure.toLowerCase());
  if (match == null) return null;
  final value = double.parse(match[1]!);
  return match[2] == 'oz' ? value * 28.3495 : value * 453.592;
}

/// [portion]'s count, with USDA's two-decimal thirds read as thirds: one
/// of "0.33 package (10 oz)" is 3 × its weight, not 3.03 ×.
double _amountOf(Map<String, dynamic> portion) {
  final amount =
      ((portion['amount'] as num?) ?? (portion['value'] as num?) ?? 1)
          .toDouble();
  final thirds = (amount * 3).roundToDouble();
  return (amount * 3 - thirds).abs() < 0.02 ? thirds / 3 : amount;
}

/// [measure] with the noun it counts made singular — "slices (6 per pkg.)"
/// to "slice (6 per pkg.)", "pea pods" to "pea pod" — for a count divided
/// down to one. The noun is the last word before any comma or parenthesis.
String singularMeasure(String measure) {
  final headEnd = measure.indexOf(RegExp(r'[,(]'));
  final head = headEnd < 0 ? measure : measure.substring(0, headEnd);
  final match = RegExp(r'[A-Za-z]+(?=\s*$)').firstMatch(head);
  if (match == null) return measure;
  final word = match[0]!;
  final lower = word.toLowerCase();
  final String singular;
  if (_irregularPlurals[lower] case final irregular?) {
    singular = irregular;
  } else if (lower.endsWith('ies')) {
    singular = '${word.substring(0, word.length - 3)}y';
  } else if (lower.endsWith('oes')) {
    singular = word.substring(0, word.length - 2);
  } else if (lower.endsWith('s') && !lower.endsWith('ss')) {
    singular = word.substring(0, word.length - 1);
  } else {
    singular = word;
  }
  return measure.replaceRange(match.start, match.end, singular);
}

const _irregularPlurals = {'leaves': 'leaf', 'halves': 'half'};

/// "cup, chopped" from a USDA portion, without its count, or null when it
/// is not a Household Serving.
///
/// Foundation Foods name the unit in `measureUnit` and add a `modifier`;
/// SR Legacy leaves the unit "undetermined" and writes the whole measure
/// into `modifier` ("cup, chopped", "large").
String? servingMeasure(Map<String, dynamic> portion) {
  final unit = ((portion['measureUnit'] as Map?)?['name'] as String? ?? '')
      .trim();
  final modifier = (portion['modifier'] as String? ?? '').trim();
  final description = (portion['portionDescription'] as String? ?? '').trim();

  final String measure;
  if (unit.isNotEmpty && unit.toLowerCase() != 'undetermined') {
    if (_notHouseholdMeasures.contains(unit.toLowerCase())) return null;
    measure = modifier.isEmpty ? unit : '$unit, $modifier';
  } else if (modifier.isNotEmpty) {
    measure = modifier;
  } else if (description.isNotEmpty) {
    // Unused by the 2026-10 Foundation and 2018-04 SR Legacy files. The
    // description may carry its own count, which [householdServing] adds.
    measure = description.replaceFirst(RegExp(r'^\d+(?:\.\d+)?\s+'), '');
  } else {
    return null;
  }
  return _keepMeasure(measure) ? measure : null;
}

bool _keepMeasure(String measure) {
  final lower = measure.toLowerCase();
  if (_notHouseholdMeasures.contains(lower)) return false;
  if (_notHouseholdHead.hasMatch(lower)) return false;
  if (lower.contains('yield') || preparedWords.hasMatch(lower)) return false;
  return true;
}

/// A label serving or a weight with something after it — "NLEA serving",
/// "serving (3 oz)", "oz, boneless", "lb (2 pieces)". "fl oz" is a volume
/// and "package (2 lb)" a thing someone takes, so both stay.
final _notHouseholdHead = RegExp(r'^(?:nlea\s+)?(?:serving|oz|lb|racc)\b');

// ---------------------------------------------------------------------------
// Review report

void _writeReview(StapleFoodsResult result) {
  final dir = Directory(reviewDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  String csv(List<Object?> cells) =>
      cells.map((c) => '"${'${c ?? ''}'.replaceAll('"', '""')}"').join(',');

  final byCategory = <String, List<StapleFoodDTO>>{};
  for (final food in result.kept) {
    byCategory.putIfAbsent(food.category, () => []).add(food);
  }
  final summary = StringBuffer()..writeln(csv(['category', 'kept']));
  for (final entry
      in byCategory.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    summary.writeln(csv([entry.key, entry.value.length]));
    final rows = StringBuffer()
      ..writeln(
        csv([
          'fdcId',
          'source',
          'name',
          'kcal',
          'protein',
          'fat',
          'carbs',
          'servings',
        ]),
      );
    for (final f in entry.value) {
      rows.writeln(
        csv([
          f.fdcId,
          f.source,
          f.name,
          f.nutrients.energyKcal,
          f.nutrients.proteins,
          f.nutrients.fat,
          f.nutrients.carbohydrates,
          f.servings.map((s) => '${s.label} = ${s.gramWeight} g').join('; '),
        ]),
      );
    }
    final file = entry.key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    File('$reviewDir/kept_$file.csv').writeAsStringSync(rows.toString());
  }
  File('$reviewDir/summary.csv').writeAsStringSync(summary.toString());

  final dropped = StringBuffer()
    ..writeln(csv(['fdcId', 'source', 'category', 'reason', 'name']));
  for (final d in result.dropped) {
    dropped.writeln(csv([d.fdcId, d.source, d.category, d.reason, d.name]));
  }
  File('$reviewDir/dropped.csv').writeAsStringSync(dropped.toString());
}
