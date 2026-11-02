import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/steps_calc.dart';

void main() {
  test('10k steps at 180 cm and 90 kg is about 335 net kcal', () {
    // step length 0.414 * 1.80 m = 0.7452 m; 10000 steps = 7.452 km
    // 0.5 kcal/kg/km * 90 kg * 7.452 km = 335.34
    expect(
      StepsCalc.netWalkingKcal(steps: 10000, heightCM: 180, weightKG: 90),
      closeTo(335.34, 1e-6),
    );
  });

  test('uses total body weight, not lean mass', () {
    final heavier = StepsCalc.netWalkingKcal(
      steps: 10000,
      heightCM: 180,
      weightKG: 100,
    );
    final lighter = StepsCalc.netWalkingKcal(
      steps: 10000,
      heightCM: 180,
      weightKG: 50,
    );
    expect(heavier, closeTo(lighter * 2, 1e-9));
  });

  test('no steps, no kcal', () {
    expect(StepsCalc.netWalkingKcal(steps: 0, heightCM: 180, weightKG: 90), 0);
  });
}
