import 'package:PiliPlus/prm/progress.dart';

/// Maps only a card's explicit video/episode identity to the PRM namespace.
/// Never infer progress from history, season IDs, URLs or another media type.
abstract final class PrmVideoId {
  static String? _bvid(String? value) =>
      value != null &&
          value.startsWith('BV') &&
          PrmProgressEntry.supportsId(value)
      ? value
      : null;

  static String? _episode(Object? value) {
    // Model IDs are ints, except member-home's string param. Do not parse or
    // normalize strings: whitespace, signs, prefixes and fractions are errors.
    if (value is! int && value is! String) return null;
    final digits = value.toString();
    if (!RegExp(r'^[0-9]+$').hasMatch(digits) ||
        !RegExp(r'[1-9]').hasMatch(digits)) {
      return null;
    }
    final id = 'ep$digits';
    return PrmProgressEntry.supportsId(id) ? id : null;
  }

  static String? recommendation({
    required String? goto,
    String? bvid,
    Object? episodeId,
  }) => switch (goto) {
    'av' => _bvid(bvid),
    'bangumi' => _episode(episodeId),
    _ => null,
  };

  static String? dynamicCard({
    required String? type,
    String? bvid,
    Object? episodeId,
  }) => switch (type) {
    'DYNAMIC_TYPE_AV' || 'DYNAMIC_TYPE_UGC_SEASON' => _bvid(bvid),
    'DYNAMIC_TYPE_PGC' || 'DYNAMIC_TYPE_PGC_UNION' => _episode(episodeId),
    _ => null,
  };

  static String? favorite({
    required int? type,
    String? bvid,
    Object? episodeId,
  }) => switch (type) {
    2 => _bvid(bvid),
    24 => _episode(episodeId),
    _ => null,
  };

  static String? memberHome({
    required String? goto,
    String? bvid,
    Object? episodeId,
    bool? isPgc,
  }) => goto == 'av' && isPgc == true
      // These cards route through uri; param is an AV ID, not an episode ID.
      ? null
      : recommendation(goto: goto, bvid: bvid, episodeId: episodeId);
}
