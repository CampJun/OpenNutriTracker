import 'dart:convert';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/data/dto/staple/staple_food_dto.dart';
import 'package:opennutritracker/features/add_meal/util/backend_title.dart';
import 'package:opennutritracker/features/add_meal/util/soft_text_score.dart';

/// The Staple Foods bundled with the app (CONTEXT.md, docs/adr/0002):
/// `assets/staple_foods.json`, built by `tool/build_staple_foods.dart`.
///
/// Everything happens on the device. The asset is read and parsed once, on
/// the first search, and kept in memory — about 1,600 foods, well under a
/// megabyte.
class StapleFoodDataSource {
  static final _log = Logger('StapleFoodDataSource');

  static const assetPath = 'assets/staple_foods.json';

  /// Rows a search returns at most. A local search costs nothing to widen,
  /// and a staple query like `beef` has dozens of honest matches.
  static const maxResults = 50;

  /// Scores below this are not matches: the soft score gives every pair of
  /// tokens that share a prefix some credit, and a single shared letter
  /// pair is noise.
  static const minScore = 0.3;

  final Future<String> Function() _loadAsset;
  Future<List<_IndexedFood>>? _index;

  /// [loadAsset] is for tests; the app reads the bundled asset.
  StapleFoodDataSource({Future<String> Function()? loadAsset})
    : _loadAsset = loadAsset ?? (() => rootBundle.loadString(assetPath));

  /// Every Staple Food, parsed on first use.
  Future<List<StapleFoodDTO>> allFoods() async => [
    for (final entry in await _indexed()) entry.food,
  ];

  /// The foods with what every search reads of their names, worked out
  /// once. A failed load is not kept, so the next search tries again
  /// rather than failing for the rest of the session.
  Future<List<_IndexedFood>> _indexed() =>
      _index ??= _load().catchError((Object error, StackTrace stackTrace) {
        _index = null;
        return Future<List<_IndexedFood>>.error(error, stackTrace);
      });

  Future<List<_IndexedFood>> _load() async {
    final text = await _loadAsset();
    // Off the UI isolate: decoding and indexing ~1,600 foods is long
    // enough to drop frames on the first keystroke of a search.
    final (index, foundation, srLegacy) = await _decodeElsewhere(text);
    _log.fine(
      'Loaded ${index.length} Staple Foods '
      '(Foundation $foundation, SR Legacy $srLegacy)',
    );
    return index;
  }

  /// Static, so the closure [Isolate.run] sends holds only [text].
  static Future<(List<_IndexedFood>, Object?, Object?)> _decodeElsewhere(
    String text,
  ) => Isolate.run(() => _parseAndIndex(text));

  /// The Staple Foods matching [query], best first.
  ///
  /// Scored as the backend's rows were (`rankAndTruncateFoodsByName` in
  /// `sp_food_data_source.dart`), so words match in any order and by
  /// prefix — `eggs` finds "Egg" — and a USDA name's qualifiers count only
  /// where the query names them: on `chicken`, every "Chicken, …" record
  /// scores alike, and `chicken breast raw` lifts the raw breasts above
  /// them. Ties go to the food whose matching words come earliest in its
  /// name — "Oil, olive, …" before "Oil, corn, peanut, and olive" on
  /// `olive oil` — then to the shorter name, which for USDA is the plainer
  /// food, then to Foundation Foods.
  Future<List<StapleFoodDTO>> search(String query) async {
    final queryTokens = tokenize(query);
    if (queryTokens.isEmpty) return const [];
    final index = await _indexed();
    final scored = [
      for (final entry in index)
        if (scoreTokens(
              entry.titleTokens,
              queryTokens,
              qualifierTokens: entry.qualifierTokens,
            )
            case final score when score >= minScore)
          (
            entry: entry,
            score: score,
            position: _matchPosition(entry.nameTokens, queryTokens),
          ),
    ];
    mergeSort(
      scored,
      compare: (a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byPosition = a.position.compareTo(b.position);
        if (byPosition != 0) return byPosition;
        final byLength = a.entry.nameLength.compareTo(b.entry.nameLength);
        if (byLength != 0) return byLength;
        return _foundationFirst(
          a.entry.food,
        ).compareTo(_foundationFirst(b.entry.food));
      },
    );
    return [for (final e in scored.take(maxResults)) e.entry.food];
  }

  static int _foundationFirst(StapleFoodDTO food) =>
      food.source == StapleFoodDTO.foundationSource ? 0 : 1;
}

/// [name]'s title plus the qualifiers [queryTokens] name, scored against
/// them — the rule the resolver and the backend cut share (`scoreText`).
double scoreStapleFood(String name, Set<String> queryTokens) => scoreTokens(
  tokenize(deriveTitle(name)),
  queryTokens,
  qualifierTokens: _qualifierTokens(name),
);

Set<String>? _qualifierTokens(String name) {
  final qualifiers = deriveQualifiers(name);
  return qualifiers == null ? null : tokenize(qualifiers);
}

/// How far into [name] the [queryTokens] are found: the sum, over the query
/// tokens, of the position of the first name token each agrees with
/// ([_missing] when it agrees with none). Lower is earlier.
int matchPosition(String name, Set<String> queryTokens) =>
    _matchPosition(tokenize(name).toList(), queryTokens);

int _matchPosition(List<String> nameTokens, Set<String> queryTokens) {
  var total = 0;
  for (final query in queryTokens) {
    final index = nameTokens.indexWhere(
      (token) => tokenSimilarity(query, token) >= _agreement,
    );
    total += index < 0 ? _missing : index;
  }
  return total;
}

/// What a query token found nowhere in the name costs [matchPosition]:
/// more than any position, so between two names that each miss a token,
/// the one whose found tokens come earlier still wins — "Beans, pinto, …"
/// before "Beans, cannellini, dry" on `dry pinto beans`.
const _missing = 1000;

/// USDA's note on records it also distributes. It says nothing about the
/// food, and its length would sink "Beans, pinto, mature seeds, raw (Includes
/// …)" below the sprouted and frozen pinto beans on the shorter-name
/// tie-break.
const _distributionNote =
    "(Includes foods for USDA's Food Distribution Program)";

/// [name]'s length for the shorter-name tie-break, without
/// [_distributionNote].
int rankingLength(String name) =>
    name.replaceAll(_distributionNote, '').trim().length;

/// The token agreement that counts as the same word for [matchPosition] —
/// `egg`/`eggs` yes, `apple`/`apricot` no.
const _agreement = 0.7;

/// A Staple Food with the tokens and length [StapleFoodDataSource.search]
/// reads on every query.
class _IndexedFood {
  final StapleFoodDTO food;
  final Set<String> titleTokens;
  final Set<String>? qualifierTokens;
  final List<String> nameTokens;
  final int nameLength;

  _IndexedFood(this.food)
    : titleTokens = tokenize(deriveTitle(food.name)),
      qualifierTokens = _qualifierTokens(food.name),
      nameTokens = tokenize(food.name).toList(),
      nameLength = rankingLength(food.name);
}

/// The asset's foods, indexed, with the two USDA releases it was built
/// from. Top level, so [Isolate.run] sends nothing but the text.
(List<_IndexedFood>, Object?, Object?) _parseAndIndex(String text) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  return (
    [
      for (final food in json['foods'] as List)
        _IndexedFood(
          StapleFoodDTO.fromJson((food as Map).cast<String, dynamic>()),
        ),
    ],
    json['foundationRelease'],
    json['srLegacyRelease'],
  );
}
