/// One Staple Food as `assets/staple_foods.json` carries it (see
/// CONTEXT.md and docs/adr/0002).
///
/// Written by `tool/build_staple_foods.dart` from the USDA FoodData Central
/// downloads and read by `StapleFoodDataSource`. Pure Dart, no Flutter, so
/// the converter can import it: the JSON shape is defined once, here.
///
/// Every nutrient value is per 100 g of Edible Portion, in the units
/// `MealNutrimentsEntity` uses (g for macros and lipids, mg for cholesterol
/// and minerals, and the unit noted beside each vitamin).
class StapleFoodDTO {
  /// The USDA FDC id of the record the food was taken from.
  final int fdcId;

  /// `fdc_foundation` or `fdc_sr_legacy` — the backend's own source codes,
  /// so the app's existing source labels name the dataset.
  final String source;

  /// The USDA description, verbatim.
  final String name;

  /// The USDA food category description.
  final String category;

  final StapleNutrientsDTO nutrients;

  /// Household Servings in USDA's order. Empty when USDA lists none that
  /// can be measured; grams always work.
  final List<StapleServingDTO> servings;

  const StapleFoodDTO({
    required this.fdcId,
    required this.source,
    required this.name,
    required this.category,
    required this.nutrients,
    this.servings = const [],
  });

  static const foundationSource = 'fdc_foundation';
  static const srLegacySource = 'fdc_sr_legacy';

  factory StapleFoodDTO.fromJson(Map<String, dynamic> json) => StapleFoodDTO(
    fdcId: (json['id'] as num).toInt(),
    source: json['src'] as String,
    name: json['name'] as String,
    category: json['cat'] as String,
    nutrients: StapleNutrientsDTO.fromJson(
      (json['n'] as Map).cast<String, dynamic>(),
    ),
    servings: [
      for (final s in (json['sv'] as List?) ?? const [])
        StapleServingDTO.fromJson(s as List),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': fdcId,
    'src': source,
    'name': name,
    'cat': category,
    'n': nutrients.toJson(),
    if (servings.isNotEmpty) 'sv': [for (final s in servings) s.toJson()],
  };
}

/// A Household Serving: what the user reads, and what one weighs.
class StapleServingDTO {
  /// "1 cup, chopped", "1 large", "1 tbsp".
  final String label;

  /// Grams of Edible Portion in one of [label]. Always greater than zero.
  final double gramWeight;

  const StapleServingDTO({required this.label, required this.gramWeight});

  factory StapleServingDTO.fromJson(List json) => StapleServingDTO(
    label: json[0] as String,
    gramWeight: (json[1] as num).toDouble(),
  );

  List<Object> toJson() => [label, gramWeight];
}

/// Per-100 g nutrient values; null where USDA has no value.
class StapleNutrientsDTO {
  final double energyKcal;
  final double? carbohydrates;
  final double? fat;
  final double? proteins;
  final double? sugars;
  final double? saturatedFat;
  final double? fiber;
  final double? monounsaturatedFat;
  final double? polyunsaturatedFat;
  final double? transFat;
  final double? cholesterol; // mg
  final double? sodium; // mg
  final double? potassium; // mg
  final double? magnesium; // mg
  final double? calcium; // mg
  final double? iron; // mg
  final double? zinc; // mg
  final double? phosphorus; // mg
  final double? vitaminA; // µg RAE
  final double? vitaminC; // mg
  final double? vitaminD; // µg
  final double? vitaminB6; // mg
  final double? vitaminB12; // µg
  final double? niacin; // mg

  const StapleNutrientsDTO({
    required this.energyKcal,
    this.carbohydrates,
    this.fat,
    this.proteins,
    this.sugars,
    this.saturatedFat,
    this.fiber,
    this.monounsaturatedFat,
    this.polyunsaturatedFat,
    this.transFat,
    this.cholesterol,
    this.sodium,
    this.potassium,
    this.magnesium,
    this.calcium,
    this.iron,
    this.zinc,
    this.phosphorus,
    this.vitaminA,
    this.vitaminC,
    this.vitaminD,
    this.vitaminB6,
    this.vitaminB12,
    this.niacin,
  });

  static double? _d(Map<String, dynamic> json, String key) =>
      (json[key] as num?)?.toDouble();

  factory StapleNutrientsDTO.fromJson(Map<String, dynamic> j) =>
      StapleNutrientsDTO(
        energyKcal: (j['kcal'] as num).toDouble(),
        carbohydrates: _d(j, 'carb'),
        fat: _d(j, 'fat'),
        proteins: _d(j, 'prot'),
        sugars: _d(j, 'sugar'),
        saturatedFat: _d(j, 'sfa'),
        fiber: _d(j, 'fiber'),
        monounsaturatedFat: _d(j, 'mufa'),
        polyunsaturatedFat: _d(j, 'pufa'),
        transFat: _d(j, 'tfa'),
        cholesterol: _d(j, 'chol'),
        sodium: _d(j, 'na'),
        potassium: _d(j, 'k'),
        magnesium: _d(j, 'mg'),
        calcium: _d(j, 'ca'),
        iron: _d(j, 'fe'),
        zinc: _d(j, 'zn'),
        phosphorus: _d(j, 'p'),
        vitaminA: _d(j, 'vitA'),
        vitaminC: _d(j, 'vitC'),
        vitaminD: _d(j, 'vitD'),
        vitaminB6: _d(j, 'b6'),
        vitaminB12: _d(j, 'b12'),
        niacin: _d(j, 'b3'),
      );

  Map<String, dynamic> toJson() {
    final entries = <String, double?>{
      'kcal': energyKcal,
      'carb': carbohydrates,
      'fat': fat,
      'prot': proteins,
      'sugar': sugars,
      'sfa': saturatedFat,
      'fiber': fiber,
      'mufa': monounsaturatedFat,
      'pufa': polyunsaturatedFat,
      'tfa': transFat,
      'chol': cholesterol,
      'na': sodium,
      'k': potassium,
      'mg': magnesium,
      'ca': calcium,
      'fe': iron,
      'zn': zinc,
      'p': phosphorus,
      'vitA': vitaminA,
      'vitC': vitaminC,
      'vitD': vitaminD,
      'b6': vitaminB6,
      'b12': vitaminB12,
      'b3': niacin,
    };
    return {
      for (final e in entries.entries)
        if (e.value != null) e.key: e.value,
    };
  }
}
