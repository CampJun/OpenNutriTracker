class StepsCalc {
  /// Step length as a share of height. A rule of thumb: the 0.413 (female)
  /// / 0.415 (male) factors that circulate are traced to a 1993 ICHPER
  /// journal article that we could not read, so this sex-neutral midpoint is
  /// unattributed until someone finds the page.
  static const double stepLengthPerHeight = 0.414;

  /// Net energy cost of level walking, kcal per kg of body weight per km.
  ///
  /// ACSM walking equation, horizontal component: 0.1 mL O2 / kg / m above
  /// rest, at 5 kcal per L O2 -> 0.0005 kcal / kg / m.
  /// American College of Sports Medicine. ACSM's Guidelines for Exercise
  /// Testing and Prescription, metabolic equations.
  static const double netKcalPerKgPerKm = 0.5;

  /// Net walking kcal for [steps]: energy above resting burn, since resting
  /// burn is already in TDEE. Uses total body weight, because walking moves
  /// the whole body regardless of its composition.
  static double netWalkingKcal({
    required int steps,
    required double heightCM,
    required double weightKG,
  }) {
    final distanceKm = steps * stepLengthPerHeight * heightCM / 100 / 1000;
    return netKcalPerKgPerKm * weightKG * distanceKm;
  }
}
