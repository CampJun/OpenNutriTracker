import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/food_catalogue.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/add_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_meal_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/favourite_toggle_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/food_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/products_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/bloc/recent_meal_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/food_search_tab_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_favourites.dart';
import '../../../helpers/test_l10n.dart';

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getRecentIntake() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  final bool imperial;

  _FakeGetConfigUsecase({this.imperial = false});

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    usesImperialFoodUnits: imperial,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeSearch implements SearchProductsUseCase {
  @override
  Future<SearchProductsResult> searchOFFProductsByString(
    String searchString, {
    bool skipRemote = false,
  }) async => const SearchProductsResult(
    meals: <MealEntity>[],
    remoteSourceEmpty: true,
  );

  @override
  Future<SearchProductsResult> searchFDCFoodByString(
    String searchString, {
    bool skipRemote = false,
    bool forResolution = false,
  }) async => const SearchProductsResult(
    meals: <MealEntity>[],
    remoteSourceEmpty: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

final getIt = GetIt.instance;
FakeFavourites? _favourites;

Future<void> _register({bool imperial = false}) async {
  await getIt.reset();
  final config = _FakeGetConfigUsecase(imperial: imperial);
  final search = _FakeSearch();
  getIt.registerFactory<AddMealBloc>(() => AddMealBloc(config));
  getIt.registerFactory<ProductsBloc>(() => ProductsBloc(search, config));
  getIt.registerFactory<FoodBloc>(() => FoodBloc(search, config));
  getIt.registerFactory<RecentMealBloc>(
    () => RecentMealBloc(_FakeGetIntakeUsecase(), config),
  );
  await _favourites?.dispose();
  final favourites = _favourites = FakeFavourites();
  getIt.registerFactory<FavouriteMealBloc>(
    () => FavouriteMealBloc(favourites.get, config),
  );
  getIt.registerFactory<FavouriteToggleBloc>(
    () => FavouriteToggleBloc(favourites.get, favourites.toggle),
  );
}

/// The add-food screen at the root, and a stub for every route it pushes
/// that records what it was asked for.
Widget _app(List<RouteSettings> pushed) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  onGenerateRoute: (settings) {
    if (settings.name == Navigator.defaultRouteName) {
      return MaterialPageRoute<void>(
        settings: RouteSettings(
          name: settings.name,
          arguments: AddMealScreenArguments(
            AddMealType.breakfastType,
            DateTime(2026, 10, 18),
          ),
        ),
        builder: (_) => const AddMealScreen(),
      );
    }
    pushed.add(settings);
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const Scaffold(body: SizedBox()),
    );
  },
);

/// The add-food screen and the recipe builder's ingredient search with this
/// fork's food sources: Staple Foods only, no Open Food Facts, no scanner
/// (docs/adr/0002).
void main() {
  setUp(FoodCatalogue.resetForTesting);
  tearDown(() => FoodCatalogue.setForTesting(network: true, scanner: true));

  testWidgets('add food: no barcode tile and no Products chip', (tester) async {
    await _register();
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();

    expect(find.bySemanticsIdentifier('add-meal-method-barcode'), findsNothing);
    expect(find.bySemanticsIdentifier('add-meal-method-photo'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier('add-meal-method-describe'),
      findsOneWidget,
    );
    expect(find.text(l10nEn.searchProductsPage), findsNothing);
    expect(find.text(l10nEn.searchFoodPage), findsOneWidget);
  });

  testWidgets('a typed barcode is searched, not scanned', (tester) async {
    await _register();
    final pushed = <RouteSettings>[];
    await tester.pumpWidget(_app(pushed));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '4000417025005');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    // Past the search-as-you-type debounce, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(pushed, isEmpty);
  });

  testWidgets('recipe ingredient search: Food and Recent, no Products', (
    tester,
  ) async {
    await _register();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: FoodSearchTabView(
            onMealSelected: (_) {},
            onBarcodePressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10nEn.searchProductsPage), findsNothing);
    expect(find.text(l10nEn.searchFoodPage), findsOneWidget);
    expect(find.text(l10nEn.recentlyAddedLabel), findsOneWidget);
    expect(find.bySemanticsIdentifier('meal-search-barcode'), findsNothing);
  });
}
