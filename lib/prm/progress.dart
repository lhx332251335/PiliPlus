/// One server record. Wire validity is independent of supported cover IDs.
class PrmProgressEntry {
  const PrmProgressEntry._({
    required this.videoId,
    required this.part,
    required this.seq,
    required this.kind,
    required this.duration,
    required this.position,
    required this.ratio,
    required this.finished,
    required this.itemId,
    required this.title,
    required this.watchedAt,
    required this.finishedAt,
  });

  static final _idPattern = RegExp(r'^(?:BV[0-9A-Za-z]{10}|ep[0-9]+)$');
  static bool supportsId(String? id) =>
      id != null &&
      id.length <= 80 &&
      _idPattern.firstMatch(id)?.group(0) == id;

  static bool isSafeSequence(dynamic value) =>
      value is num &&
      value.isFinite &&
      value >= 0 &&
      value <= 9007199254740991 &&
      value == value.truncateToDouble();

  factory PrmProgressEntry.fromJson(dynamic value) {
    if (value is! Map) throw const FormatException('服务器进度条目格式不正确');
    bool text(String key, int limit, {bool empty = true}) =>
        value[key] is String &&
        (value[key] as String).length <= limit &&
        (empty || (value[key] as String).isNotEmpty);
    bool nullableText(String key) =>
        value.containsKey(key) && (value[key] == null || value[key] is String);
    bool number(String key) =>
        value.containsKey(key) &&
        (value[key] == null ||
            (value[key] is num &&
                (value[key] as num).isFinite &&
                (value[key] as num) >= 0));
    if (!text('videoId', 200, empty: false) ||
        !text('part', 500) ||
        !value.containsKey('kind') ||
        !(value['kind'] == null || text('kind', 500)) ||
        !isSafeSequence(value['seq']) ||
        !number('duration') ||
        !number('position') ||
        !number('ratio') ||
        (value['ratio'] != null && (value['ratio'] as num) > 1) ||
        value['finished'] is! bool ||
        !['itemId', 'title', 'watchedAt', 'finishedAt'].every(nullableText)) {
      throw const FormatException('服务器进度条目格式不正确');
    }
    return PrmProgressEntry._(
      videoId: value['videoId'] as String,
      part: value['part'] as String,
      seq: (value['seq'] as num).toInt(),
      kind: value['kind'] as String?,
      duration: (value['duration'] as num?)?.toDouble(),
      position: (value['position'] as num?)?.toDouble(),
      ratio: (value['ratio'] as num?)?.toDouble(),
      finished: value['finished'] as bool,
      itemId: value['itemId'] as String?,
      title: value['title'] as String?,
      watchedAt: value['watchedAt'] as String?,
      finishedAt: value['finishedAt'] as String?,
    );
  }

  final String videoId;
  final String part;
  final int seq;
  final String? kind;
  final double? duration;
  final double? position;
  final double? ratio;
  final bool finished;
  final String? itemId;
  final String? title;
  final String? watchedAt;
  final String? finishedAt;

  bool get supported => supportsId(videoId);
  double? get effectiveRatio {
    if (ratio != null) return ratio;
    if (position != null && duration != null && duration! > 0) {
      return (position! / duration!).clamp(0.0, 1.0);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'part': part,
    'seq': seq,
    'kind': kind,
    'duration': duration,
    'position': position,
    'ratio': ratio,
    'finished': finished,
    'itemId': itemId,
    'title': title,
    'watchedAt': watchedAt,
    'finishedAt': finishedAt,
  };
}

/// Null summary means no known record, never "not watched".
class PrmProgressSummary {
  const PrmProgressSummary({
    required this.badge,
    required this.ratio,
    required this.tooltip,
  });

  final String badge;
  final double? ratio;
  final String tooltip;

  static PrmProgressSummary? fromEntries(Iterable<PrmProgressEntry> entries) {
    if (entries.isEmpty) return null;
    PrmProgressEntry? whole;
    var latest = entries.first;
    int timestamp(PrmProgressEntry entry) =>
        DateTime.tryParse(entry.watchedAt ?? '')?.millisecondsSinceEpoch ?? 0;
    for (final entry in entries) {
      if (entry.part.isEmpty) whole = entry;
      if (timestamp(entry) > timestamp(latest)) latest = entry;
    }
    final selected = whole ?? latest;
    final partialOnly = whole == null;
    final finished = !partialOnly && selected.finished;
    final progress = selected.effectiveRatio;
    final label = finished
        ? '已看完'
        : selected.position != null
        ? '看到 ${_time(selected.position)} / ${_time(selected.duration)}'
        : progress != null
        ? '看到 ${(progress * 100).round()}%'
        : '有观看记录（进度未知）';
    final watched = DateTime.tryParse(
      (latest.watchedAt?.isNotEmpty ?? false)
          ? latest.watchedAt!
          : (selected.watchedAt ?? ''),
    )?.toLocal();
    final date = watched == null
        ? '未知'
        : '${watched.year.toString().padLeft(4, '0')}-${_pad(watched.month)}-${_pad(watched.day)} '
              '${_pad(watched.hour)}:${_pad(watched.minute)}:${_pad(watched.second)}';
    return PrmProgressSummary(
      badge: partialOnly
          ? '有分 P 记录'
          : finished
          ? '已看完'
          : progress != null
          ? '看到 ${(progress * 100).round()}%'
          : '有记录',
      ratio: partialOnly
          ? null
          : finished
          ? 1.0
          : progress,
      tooltip:
          '${partialOnly ? '分 P 记录 · ' : ''}$label\n'
          '最高进度（不是上次退出位置）\n最近观看：$date'
          '${finished ? '\nPRM 已记录完成（不代表逐秒观看100%）' : ''}'
          '${partialOnly ? '\n仅有分 P 记录，无法推断整视频进度' : ''}',
    );
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _time(double? seconds) {
    if (seconds == null) return '未知';
    final n = seconds.floor();
    return n >= 3600
        ? '${n ~/ 3600}:${_pad(n ~/ 60 % 60)}:${_pad(n % 60)}'
        : '${n ~/ 60}:${_pad(n % 60)}';
  }
}
