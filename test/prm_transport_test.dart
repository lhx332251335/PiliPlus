import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/prm/service.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

// Use dart:io's real client, not the widget binding's HTTP-400 mock. Scope the
// override around all asynchronous work: Dio constructs its client lazily.
// Do not change HttpOverrides.global, which could affect other tests.
class _LoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

Future<void> _withRealHttp(Future<void> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _LoopbackHttpOverrides());

// Real loopback connections exercise the shipped transport, not a fake adapter.
// All credentials/records are synthetic; no production PRM server is contacted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real GET sends only the fixed endpoint headers and handles 304',
    () => _withRealHttp(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: DioPrmProgressTransport.createSecureHttpClient,
        );
      addTearDown(() => dio.close(force: true));
      final transport = DioPrmProgressTransport(dio: dio);
      final received = <HttpRequest>[];
      final requestBodies = <String>[];
      final subscription = server.listen((request) async {
        received.add(request);
        requestBodies.add(await utf8.decoder.bind(request).join());
        if (request.headers.value('if-none-match') == '"synthetic-etag"') {
          request.response.statusCode = HttpStatus.notModified;
        } else {
          request.response.headers.set(
            HttpHeaders.etagHeader,
            '"synthetic-etag"',
          );
          // Even a server-supplied session cookie must not be sent on the next GET.
          request.response.cookies.add(
            Cookie('synthetic-session', 'do-not-send'),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'platform': 'bilibili', 'items': []}),
          );
        }
        await request.response.close();
      });
      addTearDown(subscription.cancel);

      final uri = Uri.parse(
        'http://127.0.0.1:${server.port}/prefix/api/v1/media/progress'
        '?platform=bilibili&since=0&limit=5000',
      );
      final first = await transport.get(uri, token: 'synthetic-readonly');
      expect(first.statusCode, HttpStatus.ok);
      expect(first.etag, '"synthetic-etag"');
      expect(jsonDecode(first.data as String), {
        'platform': 'bilibili',
        'items': <dynamic>[],
      });
      final second = await transport.get(
        uri,
        token: 'synthetic-readonly',
        etag: first.etag,
      );
      expect(second.statusCode, HttpStatus.notModified);
      expect(received, hasLength(2));
      expect(requestBodies, ['', '']);
      expect(received.first.headers.value('if-none-match'), isNull);
      expect(received.last.headers.value('if-none-match'), '"synthetic-etag"');
      for (final request in received) {
        expect(request.method, 'GET');
        expect(request.uri.path, '/prefix/api/v1/media/progress');
        expect(request.uri.queryParameters, {
          'platform': 'bilibili',
          'since': '0',
          'limit': '5000',
        });
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-readonly',
        );
        expect(request.headers.value('accept'), 'application/json');
        expect(request.headers.value('cache-control'), 'no-store');
        expect(request.headers.value('cookie'), isNull);
      }
    }),
  );

  test(
    'real redirect never contacts the target or forwards the token',
    () => _withRealHttp(() async {
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => target.close(force: true));
      final targetRequests = <HttpRequest>[];
      final targetSubscription = target.listen((request) async {
        targetRequests.add(request);
        await request.response.close();
      });
      addTearDown(targetSubscription.cancel);
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      final originRequests = <HttpRequest>[];
      final originSubscription = origin.listen((request) async {
        originRequests.add(request);
        request.response.statusCode = int.parse(
          request.uri.queryParameters['status']!,
        );
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${target.port}/must-not-contact',
        );
        await request.response.close();
      });
      addTearDown(originSubscription.cancel);
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: DioPrmProgressTransport.createSecureHttpClient,
        );
      addTearDown(() => dio.close(force: true));
      final transport = DioPrmProgressTransport(dio: dio);
      const statuses = [301, 302, 303, 307, 308];
      for (final status in statuses) {
        final response = await transport.get(
          Uri.parse(
            'http://127.0.0.1:${origin.port}/api/v1/media/progress?status=$status',
          ),
          token: 'synthetic-readonly',
        );
        expect(response.statusCode, status);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(originRequests, hasLength(statuses.length));
      for (final request in originRequests) {
        expect(request.method, 'GET');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-readonly',
        );
        expect(request.headers.value('cookie'), isNull);
      }
      expect(targetRequests, isEmpty);
    }),
  );
}
