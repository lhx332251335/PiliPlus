import 'package:PiliPlus/pages/prm_settings/view.dart';
import 'package:PiliPlus/prm/overlay.dart';
import 'package:PiliPlus/prm/service.dart';
import 'package:PiliPlus/prm/progress.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorage implements PrmProgressStorage {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> value) async => this.value = value;
}

class _SyntheticTransport implements PrmProgressTransport {
  int requests = 0;
  bool fail = false;
  @override
  Future<PrmProgressResponse> get(
    Uri uri, {
    required String token,
    String? etag,
  }) async {
    requests++;
    if (fail) throw StateError('synthetic transport Bearer $token');
    if (requests > 1) return const PrmProgressResponse(304);
    return const PrmProgressResponse(
      200,
      data: {
        'platform': 'bilibili',
        'cursor': 1,
        'nextSince': 1,
        'hasMore': false,
        'items': [
          {
            'videoId': 'BV1xx411c7mD',
            'part': '',
            'seq': 1,
            'kind': 'video',
            'duration': 100,
            'position': 42,
            'ratio': 0.42,
            'finished': false,
            'itemId': null,
            'title': null,
            'watchedAt': null,
            'finishedAt': null,
          },
        ],
      },
    );
  }
}

void main() {
  const partial = PrmProgressSummary(
    badge: '看到 42%',
    ratio: 0.42,
    tooltip: 'PRM 整体进度 42%',
  );
  const finished = PrmProgressSummary(
    badge: '已看完',
    ratio: 1,
    tooltip: 'PRM 整体已看完',
  );
  const parts = PrmProgressSummary(
    badge: '有分P记录',
    ratio: null,
    tooltip: '只有分P记录，不代表整体完成',
  );

  Widget cover(
    ValueListenable<PrmProgressSummary?> progress, {
    double width = 160,
    double height = 90,
    double scale = 1,
    Brightness brightness = Brightness.light,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              child: PrmProgressOverlay(
                videoId: 'BV1xx411c7mD',
                topRightBadge: '原生',
                summaryListenable: progress,
                child: const Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: Colors.grey),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Text('原生', style: TextStyle(fontSize: 11)),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Text('12:34', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('real overlay reacts, hides absent records and separates parts', (
    tester,
  ) async {
    final progress = ValueNotifier<PrmProgressSummary?>(null);
    addTearDown(progress.dispose);
    await tester.pumpWidget(cover(progress));
    expect(find.byKey(const ValueKey('prm-badge')), findsNothing);
    expect(find.byKey(const ValueKey('prm-progress')), findsNothing);

    progress.value = partial;
    await tester.pump();
    expect(find.text('PRM · 看到 42%'), findsOneWidget);
    expect(
      tester
          .widget<FractionallySizedBox>(
            find.byKey(const ValueKey('prm-progress')),
          )
          .widthFactor,
      0.42,
    );
    progress.value = finished;
    await tester.pump();
    expect(find.text('PRM · 已看完'), findsOneWidget);
    expect(
      tester
          .widget<FractionallySizedBox>(
            find.byKey(const ValueKey('prm-progress')),
          )
          .widthFactor,
      1,
    );
    progress.value = parts;
    await tester.pump();
    expect(find.text('PRM · 有分P记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('prm-progress')), findsNothing);
    expect(find.text('PRM · 已看完'), findsNothing);
    progress.value = null;
    await tester.pump();
    expect(find.byKey(const ValueKey('prm-badge')), findsNothing);
  });

  testWidgets('tiny covers keep a readable two-line PRM source and status', (
    tester,
  ) async {
    final progress = ValueNotifier<PrmProgressSummary?>(partial);
    addTearDown(progress.dispose);
    await tester.pumpWidget(cover(progress, width: 96, height: 54));
    expect(find.text('PRM\n42%'), findsOneWidget);
    progress.value = finished;
    await tester.pump();
    expect(find.text('PRM\n看完'), findsOneWidget);
    progress.value = parts;
    await tester.pump();
    expect(find.text('PRM\n分P'), findsOneWidget);
    expect(find.byKey(const ValueKey('prm-progress')), findsNothing);
  });

  testWidgets(
    'production service injection reacts and keeps unknown IDs absent',
    (tester) async {
      final service = PrmProgressService(
        storage: _MemoryStorage(),
        transport: _SyntheticTransport(),
        automaticRefresh: false,
      );
      addTearDown(service.dispose);
      await service.saveConfig('https://prm.test', 'synthetic-ui-token');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 90,
                  child: PrmProgressOverlay(
                    videoId: 'BV1xx411c7mD',
                    service: service,
                    child: const ColoredBox(color: Colors.grey),
                  ),
                ),
                SizedBox(
                  width: 160,
                  height: 90,
                  child: PrmProgressOverlay(
                    videoId: 'BV1xx411c7mE',
                    service: service,
                    child: const ColoredBox(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('prm-badge')), findsNothing);
      await service.refresh(force: true);
      await tester.pump();
      expect(find.text('PRM · 看到 42%'), findsOneWidget);
      expect(find.byKey(const ValueKey('prm-badge')), findsOneWidget);
      await service.saveConfig(service.baseUrl, '');
      await tester.pump();
      expect(find.byKey(const ValueKey('prm-badge')), findsNothing);
      expect(find.byKey(const ValueKey('prm-progress')), findsNothing);
    },
  );

  testWidgets(
    'settings save, sync and disable use the real service without leaking tokens',
    (tester) async {
      final storage = _MemoryStorage();
      final transport = _SyntheticTransport();
      final service = PrmProgressService(
        storage: storage,
        transport: transport,
        automaticRefresh: false,
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(home: PrmSettingsPage(service: service)),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(tester.widget<TextField>(fields.at(1)).obscureText, isTrue);
      await tester.enterText(fields.at(0), 'http://prm.test');
      await tester.pump();
      expect(find.textContaining('安全警告：HTTP'), findsOneWidget);
      await tester.enterText(fields.at(0), 'https://prm.test');
      await tester.enterText(fields.at(1), 'synthetic-ui-token');
      await tester.tap(find.text('保存并同步'));
      await tester.pumpAndSettle();
      expect(service.configured, isTrue);
      expect(service.videoCount, 1);
      expect(storage.value?['config']['token'], 'synthetic-ui-token');
      expect(find.text('已缓存视频：1'), findsOneWidget);
      expect(transport.requests, 1);
      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();
      expect(transport.requests, 2);
      transport.fail = true;
      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('同步错误：'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.contains('synthetic-ui-token') ?? false),
        ),
        findsNothing,
      );
      expect(service.lastError, isNot(contains('synthetic-ui-token')));
      await tester.tap(find.text('停用并清空进度'));
      await tester.pumpAndSettle();
      expect(service.configured, isFalse);
      expect(service.videoCount, 0);
      expect(storage.value?['config']['token'], '');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(800, 360)]) {
    testWidgets('settings remain scrollable at large text: $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PrmProgressService(
        storage: _MemoryStorage(),
        transport: _SyntheticTransport(),
        automaticRefresh: false,
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: PrmSettingsPage(service: service),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('停用并清空进度'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('使用说明'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('PRM tooltip does not steal the cover long-press', (
    tester,
  ) async {
    final progress = ValueNotifier<PrmProgressSummary?>(partial);
    addTearDown(progress.dispose);
    var longPresses = 0;
    await tester.pumpWidget(cover(progress, onLongPress: () => longPresses++));
    await tester.longPressAt(
      tester.getCenter(find.byKey(const ValueKey('prm-badge'))),
    );
    await tester.pump();
    expect(longPresses, 1);
    expect(
      find.text('PRM · ${partial.badge}\n${partial.tooltip}'),
      findsNothing,
    );
  });

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 180),
      const Size(160, 90),
      const Size(96, 54),
    ]) {
      for (final scale in [1.0, 3.0]) {
        testWidgets('cover stays bounded: $brightness $size scale=$scale', (
          tester,
        ) async {
          final progress = ValueNotifier<PrmProgressSummary?>(partial);
          addTearDown(progress.dispose);
          var taps = 0;
          await tester.pumpWidget(
            cover(
              progress,
              width: size.width,
              height: size.height,
              scale: scale,
              brightness: brightness,
              onTap: () => taps++,
            ),
          );
          expect(tester.takeException(), isNull);
          final badge = tester.getRect(find.byKey(const ValueKey('prm-badge')));
          final bounds = tester.getRect(find.byType(PrmProgressOverlay));
          expect(bounds.contains(badge.topLeft), isTrue);
          expect(bounds.contains(badge.bottomRight), isTrue);
          expect(badge.overlaps(tester.getRect(find.text('12:34'))), isFalse);
          expect(badge.overlaps(tester.getRect(find.text('原生'))), isFalse);
          final bar = tester.getRect(
            find.byKey(const ValueKey('prm-progress')),
          );
          expect(bar.width, closeTo(size.width * 0.42, 0.01));
          expect(bar.height, 3);
          await tester.tapAt(badge.center);
          await tester.pump();
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
