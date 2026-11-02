import 'package:meta/meta.dart';

/// Which food sources this fork uses (docs/adr/0002).
///
/// Food search finds the bundled Staple Foods and the user's own foods and
/// recipes, nothing from the network. Open Food Facts and the Supabase
/// backend stay in the tree but switched off, so upstream releases still
/// merge cleanly; these are the switches, read where those sources are
/// wired in.
///
/// Settable only from tests: `test/flutter_test_config.dart` switches the
/// network sources back on so upstream's tests of them keep running
/// unchanged, and this fork's tests switch them off where they test it.
abstract final class FoodCatalogue {
  static bool _networkSourcesEnabled = false;
  static bool _barcodeScannerEnabled = false;

  /// Open Food Facts text search, barcode lookup and product refresh, and
  /// the Supabase multi-source backend.
  static bool get networkSourcesEnabled => _networkSourcesEnabled;

  /// The barcode scanner. Hidden until it can look up the user's own foods
  /// (it only knew Open Food Facts).
  static bool get barcodeScannerEnabled => _barcodeScannerEnabled;

  @visibleForTesting
  static void setForTesting({required bool network, required bool scanner}) {
    _networkSourcesEnabled = network;
    _barcodeScannerEnabled = scanner;
  }

  /// This fork's configuration.
  @visibleForTesting
  static void resetForTesting() =>
      setForTesting(network: false, scanner: false);
}
