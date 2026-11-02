import 'package:opennutritracker/core/domain/entity/user_entity.dart';

class TDEECalc {
  /// TDEE is a sedentary day: exercise reaches the calorie goal only
  /// through logged activities and daily steps, never through a multiplier.
  /// See `docs/adr/0001-katch-mcardle-replaces-iom-2005.md`.
  static const double sedentaryMultiplier = 1.2;

  /// Basal metabolic rate from lean body mass, Katch-McArdle:
  ///   BMR = 370 + 21.6 x lean body mass [kg]
  ///
  /// McArdle WD, Katch FI, Katch VL. Exercise Physiology: Nutrition,
  /// Energy, and Human Performance. Lippincott Williams & Wilkins.
  static double bmrKcalKatchMcArdle(double leanBodyMassKg) =>
      370 + 21.6 * leanBodyMassKg;

  /// The user's total daily energy expenditure, or null when they have no
  /// body fat reading to derive lean body mass from.
  static double? getTDEEKcal(UserEntity userEntity) {
    final reading = userEntity.bodyFatReading;
    if (reading == null) return null;
    return bmrKcalKatchMcArdle(reading.leanBodyMassKg) * sedentaryMultiplier;
  }
}
