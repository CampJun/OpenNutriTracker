import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_fat_reading_entity.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import '../../../../helpers/test_l10n.dart';

/// Renders the transparency screen against breakdowns computed by the real
/// [KcalGoalBreakdownEntity.compute] and asserts the *displayed strings*
/// equal independently hand-computed values. This pins the whole chain —
/// math, formatting, and rounding conventions (energy rounds to nearest,
/// matching the dashboard, #1469) — so the screen cannot silently drift from the numbers the
/// rest of the app shows.
class _FakeBreakdownUsecase extends Fake
    implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;

  _FakeBreakdownUsecase(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

UserEntity _buildUser({
  UserGenderEntity gender = UserGenderEntity.male,
  CaloriesProfileEntity? caloriesProfile,
  UserWeightGoalEntity goal = UserWeightGoalEntity.loseWeight,
  double? weeklyWeightGoalKg,
  double? targetWeightKg,
  bool taperEnabled = false,
  double weightKG = 80.0,
}) {
  // Yesterday (not `day - 1`) so the date stays valid on the 1st of the
  // month; captured once so components can't straddle a midnight rollover.
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return UserEntity(
    birthday: DateTime(yesterday.year - 30, yesterday.month, yesterday.day),
    heightCM: 180.0,
    weightKG: weightKG,
    gender: gender,
    goal: goal,
    bodyFatReading: BodyFatReadingEntity(
      bodyFatPercent: 20,
      weightKg: weightKG,
    ),
    caloriesProfile: caloriesProfile,
    weeklyWeightGoalKg: weeklyWeightGoalKg,
    targetWeightKg: targetWeightKg,
    caloriesTaperEnabled: taperEnabled,
  );
}

Widget _wrap(KcalGoalBreakdownEntity breakdown, {bool usesKilojoules = false}) {
  return ChangeNotifierProvider(
    create: (_) => EnergyUnitProvider(usesKilojoules: usesKilojoules),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: KcalGoalInfoScreen(usecase: _FakeBreakdownUsecase(breakdown)),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  KcalGoalBreakdownEntity breakdown, {
  bool usesKilojoules = false,
}) async {
  // Tall viewport so the lazy ListView inflates every card — the tests
  // assert content across the whole screen, including the last cards.
  tester.view.physicalSize = const Size(1200, 4500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(breakdown, usesKilojoules: usesKilojoules));
  await tester.pumpAndSettle();
}

void main() {
  group('KcalGoalInfoScreen', () {
    // Reference case, hand-computed with Katch-McArdle.
    // Lean mass = 80 × (1 − 0.20) = 64.0
    // BMR  = 370 + 21.6 × 64.0 = 1752.4
    // TDEE = 1752.4 × 1.2 = 2102.88
    // Goal = 2102.88 − 500 + 150 + 320 = 2072.88
    KcalGoalBreakdownEntity maleBreakdown() => KcalGoalBreakdownEntity.compute(
      user: _buildUser(),
      userKcalAdjustment: 150,
      totalKcalActivities: 320,
    );

    testWidgets('shows the hand-computed input values', (tester) async {
      await _pump(tester, maleBreakdown());

      expect(find.text('180 cm'), findsOneWidget);
      expect(find.text('80.0 kg'), findsOneWidget);
      expect(find.text('20.0 %'), findsOneWidget);
      expect(find.text('Lose Weight'), findsOneWidget);
    });

    testWidgets('shows lean mass from the body fat reading', (tester) async {
      await _pump(tester, maleBreakdown());

      expect(find.textContaining('80.0 × (1 − 20.0 %)'), findsOneWidget);
      expect(find.text('64.0 kg'), findsOneWidget);
    });

    testWidgets('shows the substituted Katch-McArdle steps and rounded TDEE', (
      tester,
    ) async {
      await _pump(tester, maleBreakdown());

      expect(find.textContaining('370 + 21.6 × 64.0'), findsOneWidget);
      expect(find.textContaining('= 1752 kcal'), findsOneWidget);
      expect(find.textContaining('1752 × 1.2'), findsOneWidget);
      // Box result rounds exactly like the summary rows do.
      expect(find.textContaining('= 2103 kcal'), findsOneWidget);
      // TDEE appears twice: TDEE card result row + result card line.
      expect(find.text('2103 kcal'), findsNWidgets(2));
    });

    testWidgets('shows every goal component with an explicit sign', (
      tester,
    ) async {
      await _pump(tester, maleBreakdown());

      // Without a taper the same value fills the base row, the applied
      // row, and the result-card line.
      expect(find.text('−500 kcal'), findsNWidgets(3));
      expect(find.text('+150 kcal'), findsNWidgets(2));
      expect(find.text('+320 kcal'), findsNWidgets(2));
      expect(
        find.text(l10nEn.kcalGoalInfoAdjustmentExplanationFlat),
        findsOneWidget,
      );
    });

    testWidgets('total equals the hand-computed goal, rounded like home', (
      tester,
    ) async {
      await _pump(tester, maleBreakdown());

      // 2072.88 rounds to 2073 — identical to the dashboard (#1469).
      expect(find.text('2073 kcal'), findsOneWidget);
    });

    testWidgets('macro card shows the hand-computed gram targets', (
      tester,
    ) async {
      await _pump(tester, maleBreakdown());

      // The goal shows rounded (2073); grams still truncate, like the
      // dashboard tiles. Carbs: 2072.88 × 0.60 ÷ 4 = 310.93 → 310 g.
      // Fat: ×0.25 ÷ 9 = 57.58 → 57 g. Protein: ×0.15 ÷ 4 = 77.73 → 77 g.
      expect(find.textContaining('2073 × 60 % ÷ 4 = 310 g'), findsOneWidget);
      expect(find.textContaining('2073 × 25 % ÷ 9 = 57 g'), findsOneWidget);
      expect(find.textContaining('2073 × 15 % ÷ 4 = 77 g'), findsOneWidget);
      expect(find.text('310 g'), findsOneWidget);
      expect(find.text('57 g'), findsOneWidget);
      expect(find.text('77 g'), findsOneWidget);
    });

    testWidgets('kJ mode converts summary rows but keeps the formula in kcal', (
      tester,
    ) async {
      await _pump(tester, maleBreakdown(), usesKilojoules: true);

      // 2072.88 kcal × 4.184 = 8672.9 → 8673 kJ (rounded).
      expect(find.text('8673 kJ'), findsOneWidget);
      // 2102.88 kcal × 4.184 = 8798.5 → 8798 kJ.
      expect(find.text('8798 kJ'), findsNWidgets(2));
      // Katch-McArdle is defined in kcal, so the box must stay kcal.
      expect(find.textContaining('= 2103 kcal'), findsOneWidget);
    });

    testWidgets('taper case shows base and tapered adjustment plus the note', (
      tester,
    ) async {
      // 3 kg above a 75 kg target with the taper on → factor 0.5.
      final breakdown = KcalGoalBreakdownEntity.compute(
        user: _buildUser(
          weightKG: 78.0,
          targetWeightKg: 75.0,
          taperEnabled: true,
        ),
        totalKcalActivities: 0,
      );
      await _pump(tester, breakdown);

      expect(find.text('−500 kcal'), findsOneWidget); // base row only
      expect(find.text('−250 kcal'), findsNWidgets(2)); // applied + result
      expect(find.text(l10nEn.kcalGoalInfoTaperNote), findsOneWidget);
    });

    testWidgets('taper note is absent when no taper is active', (tester) async {
      await _pump(tester, maleBreakdown());

      expect(find.text(l10nEn.kcalGoalInfoTaperNote), findsNothing);
    });

    testWidgets('weekly rate shows its explanation and 1100-based adjustment', (
      tester,
    ) async {
      final breakdown = KcalGoalBreakdownEntity.compute(
        user: _buildUser(weeklyWeightGoalKg: -0.5),
        totalKcalActivities: 0,
      );
      await _pump(tester, breakdown);

      // −0.5 kg/week × 1100 = −550 kcal/day (base, applied, result rows).
      expect(find.text('−550 kcal'), findsNWidgets(3));
      expect(
        find.text(l10nEn.kcalGoalInfoAdjustmentExplanationWeekly),
        findsOneWidget,
      );
      expect(
        find.text(l10nEn.kcalGoalInfoAdjustmentExplanationFlat),
        findsNothing,
      );
    });

    testWidgets('gender does not change the TDEE step', (tester) async {
      for (final gender in UserGenderEntity.values) {
        final breakdown = KcalGoalBreakdownEntity.compute(
          user: _buildUser(gender: gender),
          totalKcalActivities: 0,
        );
        await _pump(tester, breakdown);

        expect(find.textContaining('= 2103 kcal'), findsOneWidget);
      }
    });

    testWidgets('custom macro split is rendered with its own percentages', (
      tester,
    ) async {
      final breakdown = KcalGoalBreakdownEntity.compute(
        user: _buildUser(),
        totalKcalActivities: 0,
        userCarbsGoalPct: 0.4,
        userFatsGoalPct: 0.3,
        userProteinsGoalPct: 0.3,
      );
      await _pump(tester, breakdown);

      expect(find.textContaining('× 40 % ÷ 4'), findsOneWidget);
      expect(find.textContaining('× 30 % ÷ 9'), findsOneWidget);
      expect(find.textContaining('× 30 % ÷ 4'), findsOneWidget);
    });
  });
}
