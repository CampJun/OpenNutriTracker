import 'dart:convert';

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
  Future<List<StapleFoodDTO>>? _foods;

  /// [loadAsset] is for tests; the app reads the bundled asset.
  StapleFoodDataSource({Future<String> Function()? loadAsset})
    : _loadAsset = loadAsset ?? (() => rootBundle.loadString(assetPath));

  /// Every Staple Food, parsed on first use.
  Future<List<StapleFoodDTO>> allFoods() => _foods ??= _parse();

  Future<List<StapleFoodDTO>> _parse() async {
    final json = jsonDecode(await _loadAsset()) as Map<String, dynamic>;
    final foods = [
      for (final food in json['foods'] as List)
        StapleFoodDTO.fromJson((food as Map).cast<String, dynamic>()),
    ];
    _log.fine(
      'Loaded ${foods.length} Staple Foods '
      '(Foundation ${json['foundationRelease']}, '
      'SR Legacy ${json['srLegacyRelease']})',
    );
    return foods;
  }

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
    final foods = await allFoods();
    final scored =
        [
              for (final food in foods)
                (food: food, score: scoreStapleFood(food.name, queryTokens)),
            ]
            .where((e) => e.score >= minScore)
            .map(
              (e) => (
                food: e.food,
                score: e.score,
                position: matchPosition(e.food.name, queryTokens),
              ),
            )
            .toList();
    mergeSort(
      scored,
      compare: (a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byPosition = a.position.compareTo(b.position);
        if (byPosition != 0) return byPosition;
        final byLength = rankingLength(
          a.food.name,
        ).compareTo(rankingLength(b.food.name));
        if (byLength != 0) return byLength;
        return _foundationFirst(a.food).compareTo(_foundationFirst(b.food));
      },
    );
    return [for (final e in scored.take(maxResults)) e.food];
  }

  static int _foundationFirst(StapleFoodDTO food) =>
      food.source == StapleFoodDTO.foundationSource ? 0 : 1;
}

/// [name]'s title plus the qualifiers [queryTokens] name, scored against
/// them — the rule the resolver and the backend cut share (`scoreText`).
double scoreStapleFood(String name, Set<String> queryTokens) => scoreText(
  deriveTitle(name),
  queryTokens,
  qualifiers: deriveQualifiers(name),
);

/// How far into [name] the [queryTokens] are found: the sum, over the query
/// tokens, of the position of the first name token each agrees with
/// ([_missing] when it agrees with none). Lower is earlier.
int matchPosition(String name, Set<String> queryTokens) {
  final nameTokens = tokenize(name).toList();
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
