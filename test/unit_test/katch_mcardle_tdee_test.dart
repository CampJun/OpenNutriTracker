import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_fat_reading_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/tdee_calc.dart';

void main() {
  UserEntity userWith({
    required double weightKG,
    BodyFatReadingEntity? reading,
  }) => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: weightKG,
    gender: UserGenderEntity.male,
    goal: UserWeightGoalEntity.maintainWeight,
    bodyFatReading: reading,
  );

  group('BodyFatReadingEntity', () {
    test('lean body mass is the reading weight minus its fat share', () {
      const reading = BodyFatReadingEntity(bodyFatPercent: 25, weightKg: 90);
      expect(reading.leanBodyMassKg, closeTo(67.5, 1e-9));
    });

    test('accepts 3..70 % and rejects anything outside', () {
      expect(BodyFatReadingEntity.isValidPercent(3), isTrue);
      expect(BodyFatReadingEntity.isValidPercent(70), isTrue);
      expect(BodyFatReadingEntity.isValidPercent(2.9), isFalse);
      expect(BodyFatReadingEntity.isValidPercent(70.1), isFalse);
    });
  });

  group('Katch-McArdle', () {
    test('BMR is 370 + 21.6 x lean body mass', () {
      // 370 + 21.6 * 67.5 = 1828
      expect(TDEECalc.bmrKcalKatchMcArdle(67.5), closeTo(1828, 1e-9));
    });

    test('TDEE is BMR x 1.2', () {
      final user = userWith(
        weightKG: 90,
        reading: const BodyFatReadingEntity(bodyFatPercent: 25, weightKg: 90),
      );
      // 1828 * 1.2 = 2193.6
      expect(TDEECalc.getTDEEKcal(user), closeTo(2193.6, 1e-9));
    });

    test('lean body mass stays pinned to the reading when weight changes', () {
      // Dieted from 90 to 85 kg without re-measuring: the reading still
      // says 67.5 kg lean, so TDEE does not move.
      final user = userWith(
        weightKG: 85,
        reading: const BodyFatReadingEntity(bodyFatPercent: 25, weightKg: 90),
      );
      expect(TDEECalc.getTDEEKcal(user), closeTo(2193.6, 1e-9));
    });

    test('there is no TDEE without a body fat reading', () {
      expect(TDEECalc.getTDEEKcal(userWith(weightKG: 90)), isNull);
    });
  });
}
