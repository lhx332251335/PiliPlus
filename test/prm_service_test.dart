import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/prm/service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'prm_progress_test.dart' show entry;

class MemoryStorage implements PrmProgressStorage {
  Map<String, dynamic>? state;
  bool failWrites = false;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> read() async => state == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(jsonEncode(state)) as Map);
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (failWrites) throw StateError('synthetic storage failure');
    final started = writeStarted;
    writeStarted = null;
    started?.complete();
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    writes++;
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class FakeTransport implements PrmProgressTransport {
  final List<Future<PrmProgressResponse> Function()> replies = [];
  final List<({Uri uri, String token, String? etag})> requests = [];
  @override
  Future<PrmProgressResponse> get(
    Uri uri, {
    required String token,
    String? etag,
  }) {
    requests.add((uri: uri, token: token, etag: etag));
    return replies.removeAt(0)();
  }

  void add(PrmProgressResponse response) => replies.add(() async => response);
}

PrmProgressResponse page(
  List<Map<String, dynamic>> items, {
  int cursor = 1,
  int? next,
  bool more = false,
  bool reset = false,
  String? etag = '"synthetic"',
}) => PrmProgressResponse(
  200,
  data: {
    'platform': 'bilibili',
    'items': items,
    'cursor': cursor,
    'nextSince': next ?? cursor,
    'hasMore': more,
    'reset': reset,
  },
  etag: etag,
);

class CallbackHttpClient implements HttpClient {
  bool Function(X509Certificate, String, int)? callback;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? value,
  ) {
    callback = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BrokenStorage implements PrmProgressStorage {
  @override
  Future<Map<String, dynamic>?> read() async =>
      throw StateError('synthetic secret');
  @override
  Future<void> write(Map<String, dynamic> value) async =>
      throw StateError('synthetic secret');
}

class RecordingAdapter implements HttpClientAdapter {
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': ['https://other.invalid'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryStorage storage;
  late FakeTransport transport;
  late PrmProgressService service;
  setUp(() async {
    storage = MemoryStorage();
    transport = FakeTransport();
    service = PrmProgressService(
      storage: storage,
      transport: transport,
      automaticRefresh: false,
    );
    await service.initialize();
    await service.saveConfig(
      'https://prm.example.invalid/prefix/',
      'synthetic-token',
    );
  });
  tearDown(() => service.dispose());

  test('all pages atomically saved; incremental merge by videoId + part; 304 restart', () async {
    transport
      ..add(page([entry()], cursor: 3, next: 1, more: true, etag: '"first"'))
      ..add(
        page([
          entry(id: 'ep2', seq: 2),
          entry(id: 'future-id', seq: 3),
        ], cursor: 3),
      );
    final writes = storage.writes;
    await service.refresh(force: true);
    expect(storage.writes, writes + 1);
    expect(service.videoCount, 2);
    expect(service.lastError, isNull);
    expect(transport.requests.map((r) => r.uri.queryParameters['since']), [
      '0',
      '1',
    ]);
    expect(transport.requests.first.uri.path, '/prefix/api/v1/media/progress');
    expect(transport.requests.first.uri.queryParameters, {
      'platform': 'bilibili',
      'since': '0',
      'limit': '5000',
    });
    expect(transport.requests.last.etag, isNull);
    transport.add(
      page([
        entry(seq: 4, ratio: 0.7),
        entry(part: 'cid', seq: 5, finished: true),
      ], cursor: 5),
    );
    await service.refresh(force: true);
    expect(transport.requests.last.etag, '"synthetic"');
    expect(transport.requests.last.uri.queryParameters['since'], '3');
    expect(service.summaryFor('BV1234567890')!.ratio, 0.7);
    expect(service.summaryFor('future-id'), isNull);
    expect(service.summaryFor('ep999'), isNull);
    service.dispose();
    service = PrmProgressService(
      storage: storage,
      transport: transport,
      automaticRefresh: false,
    );
    await service.initialize();
    expect(service.videoCount, 2);
    transport.add(const PrmProgressResponse(304));
    await service.refresh(force: true);
    expect(transport.requests.last.uri.queryParameters['since'], '5');
    expect(service.videoCount, 2);
    expect(service.lastSuccess, isNotNull);
  });

  test(
    '401, offline and failed later page preserve snapshot and cursor',
    () async {
      transport.add(page([entry()]));
      await service.refresh(force: true);
      final success = service.lastSuccess;
      for (final fail in <Future<PrmProgressResponse> Function()>[
        () async => const PrmProgressResponse(401),
        () async => throw StateError('offline synthetic-token'),
      ]) {
        transport.replies.add(fail);
        await service.refresh(force: true);
        expect(service.lastSuccess, success);
        expect(service.videoCount, 1);
        expect(service.lastError, isNotNull);
        expect(service.lastError, isNot(contains('synthetic-token')));
      }
      transport
        ..add(page([entry(id: 'ep2', seq: 2)], cursor: 3, next: 2, more: true))
        ..add(const PrmProgressResponse(500));
      await service.refresh(force: true);
      expect(service.summaryFor('ep2'), isNull);
      transport.add(const PrmProgressResponse(304));
      await service.refresh(force: true);
      expect(transport.requests.last.uri.queryParameters['since'], '1');
    },
  );

  test('reset replaces only after complete successful download', () async {
    transport.add(page([entry()]));
    await service.refresh(force: true);
    transport
      ..add(page([], cursor: 0, reset: true))
      ..add(const PrmProgressResponse(503));
    await service.refresh(force: true);
    expect(service.videoCount, 1);
    transport
      ..add(page([], cursor: 0, reset: true))
      ..add(page([entry(id: 'ep9')], etag: '"reset"'));
    await service.refresh(force: true);
    expect(transport.requests.last.uri.queryParameters['since'], '0');
    expect(transport.requests.last.etag, isNull);
    expect(service.summaryFor('BV1234567890'), isNull);
    expect(service.summaryFor('ep9'), isNotNull);
  });

  test(
    'invalid wire data, seq, pagination and later 304 cannot commit',
    () async {
      final invalid = [
        page([entry(seq: 0)]),
        page([entry(seq: 2)], cursor: 1),
        page([entry(seq: 2), entry(seq: 1)], cursor: 2),
        page([entry()..['ratio'] = -1]),
        page([], cursor: 0, next: 0, more: true),
        const PrmProgressResponse(302),
      ];
      for (final response in invalid) {
        transport.add(response);
        await service.refresh(force: true);
        expect(service.videoCount, 0);
        expect(service.lastSuccess, isNull);
        expect(service.lastError, isNotNull);
      }
      transport
        ..add(page([entry()], cursor: 2, next: 1, more: true))
        ..add(const PrmProgressResponse(304));
      await service.refresh(force: true);
      expect(service.videoCount, 0);
      transport
        ..add(page([], reset: true))
        ..add(page([], reset: true));
      await service.refresh(force: true);
      expect(service.lastError, isNotNull);
    },
  );

  test('config switch clears immediately and stale request cannot overwrite new state', () async {
    transport.add(page([entry()]));
    await service.refresh(force: true);
    final pending = Completer<PrmProgressResponse>();
    transport.replies.add(() => pending.future);
    final oldFlight = service.refresh(force: true);
    await Future<void>.delayed(Duration.zero);
    await service.saveConfig(
      'https://second.example.invalid',
      'other-synthetic',
    );
    expect(service.videoCount, 0);
    expect(service.lastSuccess, isNull);
    transport.add(page([entry(id: 'ep8')]));
    await service.refresh(force: true);
    pending.complete(page([entry(id: 'ep99', seq: 2)], cursor: 2));
    await oldFlight;
    expect(service.summaryFor('ep8'), isNotNull);
    expect(service.summaryFor('ep99'), isNull);
    expect(storage.state!['config']['token'], 'other-synthetic');
    await service.saveConfig(service.baseUrl, '');
    expect(service.configured, isFalse);
    expect(service.videoCount, 0);
  });

  test('overlapping config writes including reverting to original cannot diverge on restart', () async {
    final original = service.baseUrl;
    final gate = Completer<void>();
    final started = Completer<void>();
    storage
      ..writeGate = gate
      ..writeStarted = started;
    final first = service.saveConfig(
      'https://second.example.invalid',
      'second-synthetic',
    );
    await started.future;
    final revert = service.saveConfig(original, 'synthetic-token');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([first, revert]);
    expect(service.baseUrl, original);
    expect(storage.state!['config']['baseUrl'], original);
    service.dispose();
    service = PrmProgressService(
      storage: storage,
      transport: transport,
      automaticRefresh: false,
    );
    await service.initialize();
    expect(service.baseUrl, original);
  });

  test(
    'failed newer config save does not hide an older completed durable save',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      storage
        ..writeGate = gate
        ..writeStarted = started;
      final first = service.saveConfig(
        'https://second.example.invalid',
        'second-synthetic',
      );
      await started.future;
      final second = service.saveConfig(
        'https://third.example.invalid',
        'third-synthetic',
      );
      final failure = expectLater(second, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      storage.failWrites = true;
      gate.complete();
      await first;
      await failure;
      expect(service.baseUrl, storage.state!['config']['baseUrl']);
      expect(service.token, storage.state!['config']['token']);
    },
  );

  test(
    'config changes fence an old snapshot write already in storage',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      storage
        ..writeGate = gate
        ..writeStarted = started;
      transport.add(page([entry()]));
      final flight = service.refresh(force: true);
      await started.future;
      final change = service.saveConfig(
        'https://second.example.invalid',
        'second-synthetic',
      );
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([flight, change]);
      expect(service.videoCount, 0);
      expect(storage.state!['snapshot']['entries'], isEmpty);
      expect(storage.state!['snapshot']['cursor'], 0);
      expect(storage.state!['config']['token'], 'second-synthetic');
    },
  );

  test('URL/token validation preserves current config on rejection', () async {
    for (final url in [
      'ftp://host',
      'https://u:p@host',
      'https://host?x=1',
      'https://host#x',
      'https://host?',
      'https://host#',
      'not a URL',
    ]) {
      await expectLater(
        service.saveConfig(url, 'synthetic'),
        throwsFormatException,
      );
    }
    for (final token in ['a\r\nb', 'x' * 4097]) {
      await expectLater(
        service.saveConfig(service.baseUrl, token),
        throwsFormatException,
      );
    }
    expect(service.token, 'synthetic-token');
    await service.saveConfig('http://127.0.0.1:8080/prm/', ' synthetic ');
    expect(service.baseUrl, 'http://127.0.0.1:8080/prm');
    expect(service.token, 'synthetic');
  });

  test(
    'concurrent refresh coalesces and storage failure does not advance memory',
    () async {
      final pending = Completer<PrmProgressResponse>();
      transport.replies.add(() => pending.future);
      final first = service.refresh(force: true);
      final second = service.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests.length, 1);
      expect(service.syncing, isTrue);
      storage.failWrites = true;
      pending.complete(page([entry()]));
      await Future.wait([first, second]);
      expect(service.videoCount, 0);
      expect(service.lastSuccess, isNull);
      expect(service.lastError, isNotNull);
      expect(service.syncing, isFalse);
    },
  );

  test('automatic foreground refresh is throttled, paused suppresses automatic network', () async {
    service.dispose();
    var now = DateTime.utc(2026);
    service = PrmProgressService(
      storage: storage,
      transport: transport,
      automaticRefresh: true,
      now: () => now,
    );
    transport.add(const PrmProgressResponse(304));
    await service.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests.length, 1);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests.length, 1);
    now = now.add(const Duration(minutes: 31));
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.refresh();
    expect(transport.requests.length, 1);
    transport.add(const PrmProgressResponse(304));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests.length, 2);
  });

  test('real Hive persists config and snapshot in one isolated box key across reopen', () async {
    service.dispose();
    final dir = await Directory.systemTemp.createTemp('prm-synthetic-');
    try {
      Hive.init(dir.path);
      service = PrmProgressService(
        storage: HivePrmProgressStorage(),
        transport: transport,
        automaticRefresh: false,
      );
      await service.initialize();
      await service.saveConfig(
        'https://hive.example.invalid',
        'hive-synthetic',
      );
      transport.add(page([entry()]));
      await service.refresh(force: true);
      final box = Hive.box<dynamic>(HivePrmProgressStorage.boxName);
      expect(box.keys.toList(), [HivePrmProgressStorage.stateKey]);
      expect(Hive.isBoxOpen('setting'), isFalse);
      expect(Hive.isBoxOpen('video'), isFalse);
      service.dispose();
      await Hive.close();
      service = PrmProgressService(
        storage: HivePrmProgressStorage(),
        transport: transport,
        automaticRefresh: false,
      );
      await service.initialize();
      expect(service.baseUrl, 'https://hive.example.invalid');
      expect(service.videoCount, 1);
      expect(service.lastSuccess, isNotNull);
      transport.add(const PrmProgressResponse(304));
      await service.refresh(force: true);
      expect(transport.requests.last.uri.queryParameters['since'], '1');
    } finally {
      service.dispose();
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });

  test('failed sync error and unchanged snapshot survive restart', () async {
    transport.add(page([entry()]));
    await service.refresh(force: true);
    transport.add(const PrmProgressResponse(401));
    await service.refresh(force: true);
    final error = service.lastError;
    service.dispose();
    service = PrmProgressService(
      storage: storage,
      transport: transport,
      automaticRefresh: false,
    );
    await service.initialize();
    expect(service.lastError, error);
    expect(service.videoCount, 1);
  });

  test(
    'TLS client clears globally installed insecure certificate callbacks',
    () {
      final fake = CallbackHttpClient();
      HttpOverrides.runZoned(
        () {
          final client = DioPrmProgressTransport.createSecureHttpClient();
          expect(client, same(fake));
          expect(fake.callback, isNull);
        },
        createHttpClient: (_) =>
            fake..badCertificateCallback = (_, _, _) => true,
      );
    },
  );

  test('optional initialize degrades storage failure and never awaits startup network', () async {
    service.dispose();
    service = PrmProgressService(
      storage: BrokenStorage(),
      transport: transport,
    );
    await expectLater(service.initialize(), completes);
    expect(service.lastError, contains('无法读取'));
    expect(service.lastError, isNot(contains('synthetic secret')));
    expect(transport.requests, isEmpty);
    service.dispose();
    final pending = Completer<PrmProgressResponse>();
    transport.replies.add(() => pending.future);
    service = PrmProgressService(storage: storage, transport: transport);
    await service.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(service.syncing, isTrue);
    final writes = storage.writes;
    service.dispose();
    pending.complete(page([entry()]));
    await Future<void>.delayed(Duration.zero);
    expect(storage.writes, writes);
  });

  test('dedicated Dio sends GET only, rejects redirects, has bounded timeouts and no cookies', () async {
    final adapter = RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = DioPrmProgressTransport(dio: dio);
    final response = await client.get(
      Uri.parse('https://example.invalid/api/v1/media/progress'),
      token: 'synthetic',
      etag: '"old"',
    );
    expect(response.statusCode, 302);
    final request = adapter.request!;
    expect(request.method, 'GET');
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], 'Bearer synthetic');
    expect(request.headers['If-None-Match'], '"old"');
    expect(
      request.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('cookie')),
    );
    expect(request.connectTimeout, const Duration(seconds: 25));
    expect(request.receiveTimeout, const Duration(seconds: 25));
    expect(dio.interceptors.length, 1); // Dio's default ImplyContentType only.
  });
}
