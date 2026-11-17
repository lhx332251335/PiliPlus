import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/prm/progress.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';

/// A single atomic value contains both configuration and snapshot. Never place
/// these values in setting/video boxes (which may be exported through WebDAV).
abstract interface class PrmProgressStorage {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
}

class HivePrmProgressStorage implements PrmProgressStorage {
  static const boxName = 'prmProgress';
  static const stateKey = 'state';
  Box<dynamic>? _box;

  // GStorage.init must have called Hive.init before service.initialize().
  Future<Box<dynamic>> _open() async =>
      _box ??= await Hive.openBox<dynamic>(boxName);

  @override
  Future<Map<String, dynamic>?> read() async {
    final value = (await _open()).get(stateKey);
    if (value == null) return null;
    if (value is! Map) throw const FormatException('PRM 本机缓存格式不正确');
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> write(Map<String, dynamic> value) async =>
      (await _open()).put(stateKey, value);
}

class PrmProgressResponse {
  const PrmProgressResponse(this.statusCode, {this.data, this.etag});
  final int statusCode;
  final dynamic data;
  final String? etag;
}

abstract interface class PrmProgressTransport {
  Future<PrmProgressResponse> get(
    Uri uri, {
    required String token,
    String? etag,
  });
}

/// Deliberately independent from PiliPlus Request, Bilibili interceptors,
/// cookies, retry policies, and global TLS relaxation preferences.
class DioPrmProgressTransport implements PrmProgressTransport {
  DioPrmProgressTransport({Dio? dio}) : _dio = dio ?? _createDio();
  final Dio _dio;

  /// Reset a callback installed by HttpOverrides (including debug overrides).
  /// Null restores the platform's certificate validation; never inherit the
  /// Bilibili "allow bad certificate" preference for bearer-token requests.
  static HttpClient createSecureHttpClient() =>
      HttpClient()..badCertificateCallback = null;

  static Dio _createDio() => Dio()
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: createSecureHttpClient,
    );

  @override
  Future<PrmProgressResponse> get(
    Uri uri, {
    required String token,
    String? etag,
  }) async {
    // Explicit per-request options: no redirects, writes, cookies or retries.
    _dio.options.connectTimeout = const Duration(seconds: 25);
    final response = await _dio
        .get<dynamic>(
          uri.toString(),
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Cache-Control': 'no-store',
              'If-None-Match': ?etag,
            },
            followRedirects: false,
            maxRedirects: 0,
            sendTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 25),
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
          ),
        )
        .timeout(const Duration(seconds: 25));
    return PrmProgressResponse(
      response.statusCode ?? 0,
      data: response.data,
      etag: response.headers.value('etag'),
    );
  }
}

class _Snapshot {
  const _Snapshot({
    this.index = const {},
    this.cursor = 0,
    this.etag,
    this.lastSuccess,
    this.lastError,
  });
  final Map<String, List<PrmProgressEntry>> index;
  final int cursor;
  final String? etag;
  final DateTime? lastSuccess;
  final String? lastError;

  _Snapshot withStatus({DateTime? success, String? error}) => _Snapshot(
    index: index,
    cursor: cursor,
    etag: etag,
    lastSuccess: success ?? lastSuccess,
    lastError: error,
  );

  Map<String, dynamic> toJson() => {
    'entries': [
      for (final parts in index.values)
        for (final e in parts) e.toJson(),
    ],
    'cursor': cursor,
    'etag': etag,
    'lastSuccess': lastSuccess?.toIso8601String(),
    'lastError': lastError,
  };

  factory _Snapshot.fromJson(dynamic value) {
    if (value is! Map ||
        value['entries'] is! List ||
        !PrmProgressEntry.isSafeSequence(value['cursor']) ||
        !(value['etag'] == null || value['etag'] is String) ||
        !(value['lastSuccess'] == null || value['lastSuccess'] is String) ||
        !(value['lastError'] == null || value['lastError'] is String)) {
      throw const FormatException('PRM 本机缓存格式不正确');
    }
    final cursor = (value['cursor'] as num).toInt();
    final index = <String, List<PrmProgressEntry>>{};
    for (final raw in value['entries'] as List) {
      final entry = PrmProgressEntry.fromJson(raw);
      if (entry.seq > cursor) throw const FormatException('PRM 本机缓存游标不正确');
      if (entry.supported) _merge(index, entry);
    }
    final success = value['lastSuccess'] as String?;
    if (success != null && DateTime.tryParse(success) == null) {
      throw const FormatException('PRM 本机缓存时间不正确');
    }
    return _Snapshot(
      index: index,
      cursor: cursor,
      etag: value['etag'] as String?,
      lastSuccess: success == null ? null : DateTime.parse(success),
      lastError: value['lastError'] as String?,
    );
  }

  static void _merge(
    Map<String, List<PrmProgressEntry>> index,
    PrmProgressEntry entry,
  ) {
    final parts = List<PrmProgressEntry>.of(index[entry.videoId] ?? []);
    final position = parts.indexWhere((old) => old.part == entry.part);
    if (position < 0) {
      parts.add(entry);
    } else if (parts[position].seq <= entry.seq) {
      parts[position] = entry;
    }
    index[entry.videoId] = parts;
  }
}

class _SyncFailure implements Exception {
  const _SyncFailure(this.message);
  final String message;
}

class PrmProgressService extends ChangeNotifier with WidgetsBindingObserver {
  PrmProgressService({
    PrmProgressStorage? storage,
    PrmProgressTransport? transport,
    DateTime Function()? now,
    this.automaticRefresh = true,
  }) : _storage = storage ?? HivePrmProgressStorage(),
       _transport = transport ?? DioPrmProgressTransport(),
       _now = now ?? DateTime.now;

  static final instance = PrmProgressService();
  static const defaultBaseUrl = 'https://prm.konryu.top:60443';
  static const _refreshInterval = Duration(minutes: 30);
  final PrmProgressStorage _storage;
  final PrmProgressTransport _transport;
  final DateTime Function() _now;
  final bool automaticRefresh;
  String _baseUrl = defaultBaseUrl;
  String _token = '';
  _Snapshot _snapshot = const _Snapshot();
  Future<void>? _initializing;
  Future<void>? _flight;
  Future<void>? _configurationWrite;
  Future<void> _writeTail = Future<void>.value();
  Timer? _timer;
  DateTime? _lastAttempt;
  int _generation = 0;
  bool _initialized = false;
  bool _disposed = false;
  bool _active = true;

  String get baseUrl => _baseUrl;
  String get token => _token;
  bool get configured => _token.isNotEmpty;
  bool get syncing => _flight != null;
  DateTime? get lastSuccess => _snapshot.lastSuccess;
  String? get lastError => _snapshot.lastError;
  int get videoCount => _snapshot.index.length;

  PrmProgressSummary? summaryFor(String? videoId) =>
      PrmProgressEntry.supportsId(videoId)
      ? PrmProgressSummary.fromEntries(_snapshot.index[videoId] ?? [])
      : null;

  static String normalizeBaseUrl(String value) {
    final raw = value.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        // Empty userinfo (@), query (?) and fragment (#) also fail validation.
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'[\x00-\x20\x7f\\]').hasMatch(raw)) {
      throw const FormatException('服务器地址须为 HTTP 或 HTTPS，且不能含账号、密码、查询参数或片段');
    }
    return uri
        .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
  }

  static String _validateToken(String value) {
    if (value.length > 4096 || value.contains('\r') || value.contains('\n')) {
      throw const FormatException('令牌格式不正确');
    }
    return value.trim();
  }

  Future<void> initialize() {
    if (_disposed || _initialized) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final state = await _storage.read();
      if (_disposed) return;
      if (state != null) {
        final config = state['config'];
        if (state['schema'] != 1 ||
            config is! Map ||
            config['baseUrl'] is! String ||
            config['token'] is! String) {
          throw const FormatException('PRM 本机配置格式不正确');
        }
        final base = normalizeBaseUrl(config['baseUrl'] as String);
        final token = _validateToken(config['token'] as String);
        final snapshot = _Snapshot.fromJson(state['snapshot']);
        _baseUrl = base;
        _token = token;
        _snapshot = token.isEmpty ? const _Snapshot() : snapshot;
      }
    } catch (_) {
      // Optional integration must not prevent the application from starting.
      _snapshot = _snapshot.withStatus(error: '无法读取 PRM 本机缓存，请检查存储后重新保存设置');
    } finally {
      _initialized = true;
      if (!_disposed) {
        if (automaticRefresh) {
          final binding = WidgetsBinding.instance;
          _active =
              binding.lifecycleState == null ||
              binding.lifecycleState == AppLifecycleState.resumed;
          binding.addObserver(this);
          _timer = Timer.periodic(
            _refreshInterval,
            (_) => unawaited(refresh()),
          );
          // No network operation is awaited on the application startup path.
          scheduleMicrotask(() {
            if (!_disposed) unawaited(refresh());
          });
        }
        _notify();
      }
    }
  }

  /// HTTP is an explicit user configuration only. Settings must warn that it
  /// sends the token in cleartext and is suitable only for trusted local use.
  Future<void> saveConfig(String baseUrl, String token) async {
    final base = normalizeBaseUrl(baseUrl);
    final cleanToken = _validateToken(token);
    await initialize();
    if (_disposed) return;
    final generation = ++_generation;
    _flight =
        null; // Old network work is invalidated, not joined by new callers.
    final write = _exclusive(() async {
      if (_disposed || generation != _generation) return;
      final changed = _baseUrl != base || _token != cleanToken;
      final next = changed ? const _Snapshot() : _snapshot;
      // Even a return to the in-memory configuration must be persisted: an
      // earlier invalidated save may already have changed the on-disk value.
      await _storage.write(_state(base, cleanToken, next));
      if (_disposed) return;
      // A completed durable config save must update memory even when a newer
      // save is queued: that newer save might fail. Network generations remain
      // invalidated, and refresh waits for the pending configuration writer.
      _baseUrl = base;
      _token = cleanToken;
      _snapshot = next;
      if (changed) _lastAttempt = null;
    });
    _configurationWrite = write;
    try {
      await write;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _snapshot = _snapshot.withStatus(error: '无法保存 PRM 设置，请检查本机存储');
      }
      throw StateError('无法保存 PRM 设置，请检查本机存储');
    } finally {
      if (identical(_configurationWrite, write)) _configurationWrite = null;
      _notify();
    }
  }

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future<void>.value();
    if (!_initialized) return initialize().then((_) => refresh(force: force));
    final configWrite = _configurationWrite;
    if (configWrite != null) {
      return configWrite.then(
        (_) => refresh(force: force),
        onError: (Object _) {},
      );
    }
    if (_flight != null) return _flight!;
    if (!configured ||
        (!force &&
            (!_active ||
                (_lastAttempt != null &&
                    _now().difference(_lastAttempt!) < _refreshInterval)))) {
      return Future<void>.value();
    }
    _lastAttempt = _now();
    late final Future<void> flight;
    flight = _refresh(_generation).whenComplete(() {
      if (identical(_flight, flight)) {
        _flight = null;
        _notify();
      }
    });
    _flight = flight;
    _notify();
    return flight;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _refresh(int generation) async {
    final old = _snapshot;
    final base = _baseUrl;
    final token = _token;
    try {
      var index = Map<String, List<PrmProgressEntry>>.of(old.index);
      var since = old.cursor;
      String? etag;
      var first = true;
      var resetSeen = false;
      for (var pages = 0; ; pages++) {
        if (pages >= 10000) throw const _SyncFailure('同步分页过多，请检查服务器');
        final uri = Uri.parse('$base/api/v1/media/progress').replace(
          queryParameters: {
            'platform': 'bilibili',
            'since': '$since',
            'limit': '5000',
          },
        );
        PrmProgressResponse response;
        try {
          response = await _transport.get(
            uri,
            token: token,
            etag: first ? old.etag : null,
          );
        } catch (_) {
          // DioException contains request headers; never stringify/log it.
          throw const _SyncFailure('无法连接服务器，请检查网络、地址和证书');
        }
        if (!_current(generation)) return;
        if (response.statusCode == 304) {
          if (!first) throw const _SyncFailure('服务器在分页中返回了异常的缓存响应');
          await _commit(generation, old.withStatus(success: _now()));
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final message = switch (response.statusCode) {
            401 => '令牌无效或已吊销，请重新设置',
            403 => '令牌没有读取进度的权限',
            400 => '服务器拒绝了进度请求，请检查接口版本',
            404 => '服务器尚未提供观看进度接口，请升级 PRM',
            >= 300 && < 400 => '服务器返回重定向，已拒绝发送令牌到其他地址',
            _ => '服务器返回错误（${response.statusCode}）',
          };
          throw _SyncFailure(message);
        }
        dynamic page;
        try {
          page = response.data is String
              ? jsonDecode(response.data as String)
              : response.data;
        } catch (_) {
          throw const _SyncFailure('服务器未返回有效的进度数据');
        }
        if (page is! Map ||
            page['platform'] != 'bilibili' ||
            page['items'] is! List ||
            (page['items'] as List).length > 5000 ||
            !PrmProgressEntry.isSafeSequence(page['cursor']) ||
            !PrmProgressEntry.isSafeSequence(page['nextSince']) ||
            page['hasMore'] is! bool) {
          throw const _SyncFailure('服务器进度分页格式不正确');
        }
        if (page['reset'] == true) {
          if (resetSeen) throw const _SyncFailure('服务器重复要求重置，请稍后重试');
          resetSeen = true;
          index = {};
          since = 0;
          first = false;
          continue;
        }
        final next = (page['nextSince'] as num).toInt();
        final cursor = (page['cursor'] as num).toInt();
        final more = page['hasMore'] as bool;
        if (next < since || (more && next <= since) || next > cursor) {
          throw const _SyncFailure('服务器进度游标不正确');
        }
        var previous = since;
        for (final raw in page['items'] as List) {
          PrmProgressEntry entry;
          try {
            entry = PrmProgressEntry.fromJson(raw);
          } on FormatException {
            throw const _SyncFailure('服务器进度条目格式不正确');
          }
          if (entry.seq <= since || entry.seq > next || entry.seq < previous) {
            throw const _SyncFailure('服务器进度游标不正确');
          }
          previous = entry.seq;
          if (entry.supported) _Snapshot._merge(index, entry);
        }
        since = next; // Also advances past legal, unsupported video IDs.
        etag = response.etag;
        if (!more) break;
        first = false;
      }
      await _commit(
        generation,
        _Snapshot(index: index, cursor: since, etag: etag, lastSuccess: _now()),
      );
    } catch (error) {
      if (!_current(generation)) return;
      final failed = old.withStatus(
        error: error is _SyncFailure ? error.message : '同步失败，请检查本机存储后重试',
      );
      try {
        await _commit(generation, failed);
      } catch (_) {
        if (_current(generation)) {
          _snapshot = failed;
          _notify();
        }
      }
    }
  }

  static Map<String, dynamic> _state(
    String base,
    String token,
    _Snapshot snapshot,
  ) => {
    'schema': 1,
    'config': {'baseUrl': base, 'token': token},
    'snapshot': snapshot.toJson(),
  };

  Future<void> _commit(int generation, _Snapshot snapshot) =>
      _exclusive(() async {
        if (!_current(generation)) return;
        await _storage.write(_state(_baseUrl, _token, snapshot));
        if (!_current(generation)) return;
        _snapshot = snapshot;
        _notify();
      });

  // Serializing writes also fences an already-started old write before a
  // configuration change. Generation checks fence work queued after it.
  Future<void> _exclusive(Future<void> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && automaticRefresh) unawaited(refresh());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_initialized && automaticRefresh) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
