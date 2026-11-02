import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/met_calc.dart';

import '../fixture/physical_activity_entity_fixtures.dart';
import '../fixture/user_entity_fixtures.dart';

void main() {
  test(
    'Total Burned Kcal calculation for a young sedentary male doing moderate bicycling',
    () {
      final user = UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
      const activity = PhysicalActivityFixtures.moderateBicycling;

      // Assuming the user did bicycling for 1 hour
      double duration = 60;

      double resultKcalBurned = METCalc.getTotalBurnedKcal(
        user,
        activity,
        duration,
      );

      // Net of resting burn: (8 - 1) * 80 * (60 / 60)
      int expectedKcalBurned = 560;

      expect(resultKcalBurned.toInt(), expectedKcalBurned);
    },
  );

  test(
    'Total Burned Kcal calculation for a middle aged sedentary female doing light dancing',
    () {
      final user = UserEntityFixtures.middleAgedActiveFemaleWantingToLoseWeight;
      const activity = PhysicalActivityFixtures.lightDancing;

      // Assuming the user did bicycling for 1/2 hour
      double duration = 30;

      double resultKcalBurned = METCalc.getTotalBurnedKcal(
        user,
        activity,
        duration,
      );

      // Net of resting burn: (4 - 1) * 75 * (30 / 60)
      int expectedKcalBurned = 112;

      expect(resultKcalBurned.toInt(), expectedKcalBurned);
    },
  );
}
