import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_meal_mapper.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/util/portion_unit.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';

// The unit picker of a food with Household Servings (Staple Foods).

class _FakeAddIntakeUsecase extends Fake implements AddIntakeUsecase {}

class _FakeAddTrackedDayUsecase extends Fake implements AddTrackedDayUsecase {}

class _FakeGetKcalGoalUsecase extends Fake implements GetKcalGoalUsecase {}

class _FakeGetMacroGoalUsecase extends Fake implements GetMacroGoalUsecase {}

class _FakeGetTrackedDayUsecase extends Fake implements GetTrackedDayUsecase {}

class _FakeProductsRepository extends Fake implements ProductsRepository {}

class _FakeRemoteSearchCacheDataSource extends Fake
    implements RemoteSearchCacheDataSource {}

MealDetailBloc _buildBloc() => MealDetailBloc(
  _FakeAddIntakeUsecase(),
  _FakeAddTrackedDayUsecase(),
  _FakeGetKcalGoalUsecase(),
  _FakeGetMacroGoalUsecase(),
  _FakeGetTrackedDayUsecase(),
  _FakeProductsRepository(),
  _FakeRemoteSearchCacheDataSource(),
);

MealEntity _broccoli() => StapleFoodDTO(
  fdcId: 170379,
  source: StapleFoodDTO.srLegacySource,
  name: 'Broccoli, raw',
  category: 'Vegetables and Vegetable Products',
  nutrients: const StapleNutrientsDTO(
    energyKcal: 34,
    proteins: 2.8,
    fat: 0.4,
    carbohydrates: 6.6,
  ),
  servings: const [
    StapleServingDTO(label: '1 cup, chopped', gramWeight: 91),
    StapleServingDTO(
      label: '1 spear, extra large (8-3/4" to 10" long)',
      gramWeight: 24,
    ),
  ],
).toMealEntity();

Future<void> _pumpSheet(
  WidgetTester tester, {
  required TextEditingController quantityController,
  required String initialUnit,
  required void Function(String?, String?) onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: MealDetailBottomSheet(
          product: _broccoli(),
          day: DateTime(2026, 11, 2),
          intakeTypeEntity: IntakeTypeEntity.lunch,
          quantityTextController: quantityController,
          mealDetailBloc: _buildBloc(),
          selectedUnit: initialUnit,
          usesImperialUnits: false,
          onQuantityOrUnitChanged: onChanged,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String current, String next) async {
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a long label is shown whole, not as "Serving"', (tester) async {
    await _pumpSheet(
      tester,
      quantityController: TextEditingController(text: '100'),
      initialUnit: 'g',
      onChanged: (_, _) {},
    );
    await tester.tap(find.text('g').first);
    await tester.pumpAndSettle();

    expect(find.text('spear, extra large (24 g)'), findsWidgets);
    expect(find.textContaining('Serving'), findsNothing);
  });

  testWidgets('leaving a serving for grams keeps the amount', (tester) async {
    final quantity = TextEditingController(text: '2');
    String? cbQuantity;
    String? cbUnit;
    await _pumpSheet(
      tester,
      quantityController: quantity,
      initialUnit: portionUnit(0),
      onChanged: (q, u) {
        cbQuantity = q;
        cbUnit = u;
      },
    );

    await _pick(tester, 'cup, chopped (91 g)', 'g');

    expect(quantity.text, '182');
    expect(cbQuantity, '182');
    expect(cbUnit, 'g');
  });

  testWidgets('leaving a serving for ounces keeps the amount', (tester) async {
    final quantity = TextEditingController(text: '1');
    await _pumpSheet(
      tester,
      quantityController: quantity,
      initialUnit: portionUnit(0),
      onChanged: (_, _) {},
    );

    await _pick(tester, 'cup, chopped (91 g)', 'oz');

    expect(quantity.text, '3.2');
  });

  testWidgets('entering a serving from grams starts at one', (tester) async {
    final quantity = TextEditingController(text: '100');
    await _pumpSheet(
      tester,
      quantityController: quantity,
      initialUnit: 'g',
      onChanged: (_, _) {},
    );

    await _pick(tester, 'g', 'cup, chopped (91 g)');

    expect(quantity.text, '1');
  });
}
