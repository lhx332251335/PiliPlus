import 'package:PiliPlus/pages/prm_settings/view.dart';
import 'package:PiliPlus/prm/overlay.dart';
import 'package:PiliPlus/prm/progress.dart';
import 'package:PiliPlus/prm/service.dart';
import 'package:flutter/material.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class _MemoryStorage implements PrmProgressStorage {
  Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> value) async => this.value = value;
}

// Match main.dart's actual Material UI theme/localizations, including its GetX
// fork. Do not install Flutter SDK Material delegates: that hides mixed imports.
Widget _app(Widget home, {required bool getX}) => getX
    ? GetMaterialApp(
        theme: ThemeData(),
        locale: const Locale('zh', 'CN'),
        fallbackLocale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      )
    : MaterialApp(
        theme: ThemeData(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      );

void _expectAppLocalizations(BuildContext context) {
  expect(MaterialLocalizations.of(context), isNotNull);
  expect(
    Localizations.of<sdk.MaterialLocalizations>(
      context,
      sdk.MaterialLocalizations,
    ),
    isNull,
  );
}

void main() {
  for (final getX in [false, true]) {
    final host = getX ? 'GetMaterialApp' : 'Material UI MaterialApp';

    testWidgets(
      '$host settings render fields and a working localized back button',
      (tester) async {
        addTearDown(Get.reset);
        final service = PrmProgressService(
          storage: _MemoryStorage(),
          automaticRefresh: false,
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Builder(
                builder: (context) {
                  _expectAppLocalizations(context);
                  return TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PrmSettingsPage(service: service),
                      ),
                    ),
                    child: const Text('打开 PRM'),
                  );
                },
              ),
            ),
            getX: getX,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开 PRM'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text('PRM 只读进度'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.text('状态：未启用'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).first,
          'https://prm.test',
        );
        await tester.tap(find.text('保存并同步'));
        await tester.pumpAndSettle();
        expect(service.baseUrl, 'https://prm.test');
        expect(service.configured, isFalse);
        expect(tester.takeException(), isNull);
        final context = tester.element(find.byType(PrmSettingsPage));
        final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
        expect(find.byTooltip(backLabel), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PrmSettingsPage), findsNothing);
        expect(find.text('打开 PRM'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$host PRM records build and show a localized Tooltip without errors',
      (tester) async {
        addTearDown(Get.reset);
        final progress = ValueNotifier<PrmProgressSummary?>(null);
        addTearDown(progress.dispose);
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Builder(
                builder: (context) {
                  _expectAppLocalizations(context);
                  return Center(
                    child: SizedBox(
                      width: 160,
                      height: 90,
                      child: PrmProgressOverlay(
                        videoId: 'BV1xx411c7mD',
                        summaryListenable: progress,
                        child: const ColoredBox(color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
            getX: getX,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('prm-badge')), findsNothing);
        expect(tester.takeException(), isNull);
        progress.value = const PrmProgressSummary(
          badge: '看到 42%',
          ratio: 0.42,
          tooltip: 'PRM 整体进度 42%',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text('PRM · 看到 42%'), findsOneWidget);
        expect(find.byKey(const ValueKey('prm-progress')), findsOneWidget);
        expect(
          find.byType(Tooltip),
          findsOneWidget,
          reason: 'PRM must use the app Material UI Tooltip, not the SDK copy',
        );
        final tooltip = tester.state<TooltipState>(find.byType(Tooltip));
        expect(tooltip.ensureTooltipVisible(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('PRM · 看到 42%\nPRM 整体进度 42%'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Dispose any visible tooltip before GetX teardown.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
