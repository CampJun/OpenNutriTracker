import 'dart:async';

import 'package:opennutritracker/features/add_meal/data/food_catalogue.dart';

/// Runs before every test file.
///
/// This fork switches Open Food Facts, the Supabase backend and the barcode
/// scanner off (docs/adr/0002) but keeps their code, so upstream's tests of
/// them run as they are written: with the sources on. The fork's own tests
/// call `FoodCatalogue.resetForTesting()` where they test it switched off.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FoodCatalogue.setForTesting(network: true, scanner: true);
  await testMain();
}
