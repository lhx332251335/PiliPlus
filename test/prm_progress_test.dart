import 'package:PiliPlus/prm/progress.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> entry({
  String id = 'BV1234567890',
  String part = '',
  int seq = 1,
  double? ratio = 0.43,
  double? position = 510,
  double? duration = 1200,
  bool finished = false,
  String? watchedAt = '2026-01-02T03:04:05Z',
}) => {
  'videoId': id,
  'part': part,
  'seq': seq,
  'kind': null,
  'ratio': ratio,
  'position': position,
  'duration': duration,
  'finished': finished,
  'watchedAt': watchedAt,
  'finishedAt': null,
  'itemId': null,
  'title': null,
};

void main() {
  test(
    'supported identifiers are strict; legal unknown wire IDs remain valid',
    () {
      expect(PrmProgressEntry.supportsId('BV1234567890'), isTrue);
      expect(PrmProgressEntry.supportsId('ep123'), isTrue);
      for (final id in ['BV123', 'av12', 'ep', 'ep1\n', 'BV1234567890x']) {
        expect(PrmProgressEntry.supportsId(id), isFalse);
      }
      expect(
        PrmProgressEntry.fromJson(entry(id: 'future-id')).supported,
        isFalse,
      );
      expect(
        () => PrmProgressEntry.fromJson(entry()..['ratio'] = 1.1),
        throwsFormatException,
      );
      expect(
        () => PrmProgressEntry.fromJson(entry()..['finished'] = 1),
        throwsFormatException,
      );
      expect(
        () => PrmProgressEntry.fromJson(entry()..remove('kind')),
        throwsFormatException,
      );
    },
  );

  test(
    'whole record wins, latest watch date includes parts, no local 80% rule',
    () {
      final summary = PrmProgressSummary.fromEntries([
        PrmProgressEntry.fromJson(entry(ratio: 0.9)),
        PrmProgressEntry.fromJson(
          entry(
            part: 'cid-2',
            seq: 2,
            finished: true,
            watchedAt: '2026-02-03T00:00:00Z',
          ),
        ),
      ])!;
      expect(summary.badge, '看到 90%');
      expect(summary.ratio, 0.9);
      expect(summary.tooltip, contains('2026-02-03'));
      expect(summary.tooltip, contains('最高进度'));
      expect(summary.tooltip, contains('不是上次退出位置'));
      expect(summary.tooltip, contains('8:30 / 20:00'));
    },
  );

  test('parts-only never becomes whole completion or progress bar', () {
    final summary = PrmProgressSummary.fromEntries([
      PrmProgressEntry.fromJson(entry(part: 'cid', finished: true, ratio: 1)),
    ])!;
    expect(summary.badge, '有分 P 记录');
    expect(summary.ratio, isNull);
    expect(summary.tooltip, contains('无法推断整视频进度'));
    expect(PrmProgressSummary.fromEntries([]), isNull);
  });

  test('finished is authoritative; unknown progress stays unknown', () {
    final done = PrmProgressSummary.fromEntries([
      PrmProgressEntry.fromJson(entry(finished: true, ratio: 0.2)),
    ])!;
    expect(done.badge, '已看完');
    expect(done.ratio, 1);
    expect(done.tooltip, contains('PRM 已记录完成'));
    final unknown = PrmProgressSummary.fromEntries([
      PrmProgressEntry.fromJson(
        entry(ratio: null, position: null, duration: null, watchedAt: null),
      ),
    ])!;
    expect(unknown.badge, '有记录');
    expect(unknown.ratio, isNull);
    expect(unknown.tooltip, contains('最近观看：未知'));
    final fallback = PrmProgressSummary.fromEntries([
      PrmProgressEntry.fromJson(
        entry(ratio: null, position: 50, duration: 100),
      ),
    ])!;
    expect(fallback.ratio, 0.5);
  });
}
