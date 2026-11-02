import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/nutrition_label.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../helpers/test_l10n.dart';

/// A label read opens the custom-food form on the label's own numbers, per
/// Label Serving, with failed checks highlighted; saving scales them to per
/// 100 g and keeps every nutrient (docs/adr/0003).
void main() {
  final getIt = GetIt.instance;
  late _RecordingCustomMealDataSource dataSource;

  setUp(() {
    dataSource = _RecordingCustomMealDataSource();
    getIt.registerFactory<EditMealBloc>(
      () => EditMealBloc(
        _FakeGetConfigUsecase(),
        dataSource,
        // Remembers Simple mode, which a review must not open in.
        _FakeConfigRepository(),
        _FakeFavouriteMealRepository(),
        _RecordingIntakeRepository(),
      ),
    );
  });

  tearDown(() async => getIt.reset());

  // The sauce label, with iron misread as 1.0 mg beside its printed 10%.
  const label = NutritionLabel(
    servingSize: '2 Tbsp (31g)',
    servingGrams: 31,
    servingsPerContainer: 24,
    amounts: {
      LabelNutrient.energyKcal: 160,
      LabelNutrient.fat: 14,
      LabelNutrient.saturatedFat: 2.5,
      LabelNutrient.transFat: 0,
      LabelNutrient.cholesterol: 10,
      LabelNutrient.sodium: 190,
      LabelNutrient.carbohydrates: 7,
      LabelNutrient.fiber: 0,
      LabelNutrient.sugars: 7,
      LabelNutrient.protein: 0,
      LabelNutrient.iron: 1.0,
    },
    dailyValuePercents: {LabelNutrient.iron: 10},
  );

  Future<void> pumpReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('before')),
            ),
            MaterialPageRoute<void>(
              settings: RouteSettings(
                arguments: EditMealScreenArguments(
                  DateTime(2026, 11, 2),
                  customFoodFromLabel(label, barcode: '070200790148'),
                  IntakeTypeEntity.lunch,
                  false,
                  editOnly: true,
                  labelReview: LabelReview(label, checkNutritionLabel(label)),
                ),
              ),
              builder: (_) => const EditMealScreen(),
            ),
          ],
          onGenerateRoute: (_) => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextFormField>(find.widgetWithText(TextFormField, label))
      .controller!
      .text;

  testWidgets('opens on the label numbers with the flag shown', (tester) async {
    await pumpReview(tester);

    expect(find.text(l10nEn.labelReviewBannerFlagged), findsOneWidget);
    // Advanced, whatever mode was remembered: the toggle is hidden and the
    // micronutrients are on screen.
    expect(find.text(l10nEn.customMealFormSimple), findsNothing);
    expect(fieldText(tester, l10nEn.mealFatLabel), '14');
    expect(fieldText(tester, l10nEn.cholesterolLabel), '10');
    expect(fieldText(tester, l10nEn.transFatLabel), '0');
    expect(fieldText(tester, l10nEn.customMealBarcodeLabel), '070200790148');
    expect(fieldText(tester, l10nEn.mealNameLabel), isEmpty);
    expect(
      fieldText(tester, '${l10nEn.baseQuantityLabel} (${l10nEn.gramUnit})'),
      '31',
    );
    expect(
      find.text(l10nEn.labelFlagDailyValue('10', '1.8', 'mg')),
      findsOneWidget,
    );
  });

  testWidgets('saving scales to per 100 g and keeps every nutrient', (
    tester,
  ) async {
    await pumpReview(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, l10nEn.mealNameLabel),
      'Chick-fil-A Sauce',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();

    final (saved, _) = dataSource.saves.single;
    expect(saved.name, 'Chick-fil-A Sauce');
    expect(saved.code, '070200790148');
    expect(saved.servingQuantity, 31);
    final n = saved.nutriments;
    expect(n.energyKcal100, closeTo(516.13, 0.01));
    expect(n.fat100, closeTo(45.16, 0.01));
    expect(n.cholesterol100, closeTo(32.26, 0.01));
    expect(n.transFat100, 0);
    // Flagged, not corrected: the value saved is the one on screen.
    expect(n.iron100, closeTo(3.23, 0.01));
  });
}

class _RecordingCustomMealDataSource implements CustomMealDataSource {
  final saves = <(MealDBO, MealDBO?)>[];
  final library = <MealDBO>[];

  @override
  List<MealDBO> getAllCustomMeals() => library;

  /// When set, every save waits for it, standing in for a slow disk write.
  Completer<void>? gate;

  @override
  Future<void> saveCustomMeal(MealDBO mealDBO, {MealDBO? previous}) async {
    saves.add((mealDBO, previous));
    await gate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _RecordingIntakeRepository implements IntakeRepository {
  final moves = <(String, MealDBO)>[];

  @override
  Future<int> moveCustomMealInEveryProfile({
    required String fromMealKey,
    required MealDBO toMeal,
  }) async {
    moves.add((fromMealKey, toMeal));
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeConfigRepository implements ConfigRepository {
  @override
  Future<String?> getCustomMealFormMode() async =>
      CustomMealFormMode.simple.name;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// #1307 moves a favourite along with the edit; nothing is starred here.
class _FakeFavouriteMealRepository implements FavouriteMealRepository {
  @override
  Future<void> moveFavourite(MealEntity previous, MealEntity updated) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
