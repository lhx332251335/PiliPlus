import 'package:PiliPlus/prm/service.dart';
import 'package:material_ui/material_ui.dart';

class PrmSettingsPage extends StatefulWidget {
  const PrmSettingsPage({super.key, this.service});

  final PrmProgressService? service;

  @override
  State<PrmSettingsPage> createState() => _PrmSettingsPageState();
}

class _PrmSettingsPageState extends State<PrmSettingsPage> {
  late final PrmProgressService _service;
  late final TextEditingController _address;
  late final TextEditingController _token;
  bool _busy = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PrmProgressService.instance;
    _address = TextEditingController(text: _service.baseUrl);
    _token = TextEditingController(text: _service.token);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.initialize();
      if (!mounted) return;
      _address.text = _service.baseUrl;
      _token.text = _service.token;
    } catch (_) {
      _message = '无法加载本机 PRM 配置，请重试。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (_) {
      // Never render exception text: transport errors may contain credentials.
      if (mounted) _message = '操作失败，请检查地址、令牌和网络后重试。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _safeError() {
    // Even encoded credentials can occur in transport error diagnostics.
    // Show a credential-free status rather than interpolating raw errors.
    return _service.lastError?.isNotEmpty == true
        ? '同步失败，请检查地址、令牌、网络和 PRM 服务状态。'
        : null;
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PRM 只读进度')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final busy = _busy || _service.syncing;
          final error = _safeError();
          final http = Uri.tryParse(_address.text.trim())?.scheme == 'http';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _address,
                enabled: !busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'PRM 服务地址',
                  hintText: 'https://prm.example.com',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _token,
                enabled: !busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '只读令牌',
                  helperText: '仅用于读取 PRM；不会展示或记录令牌',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (http) ...[
                Text(
                  '安全警告：HTTP 不加密，地址、令牌及进度可能被窃听。建议使用 HTTPS；仅在可信网络使用 HTTP。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => _run(() async {
                            await _service.saveConfig(
                              _address.text.trim(),
                              _token.text,
                            );
                            if (_service.configured) {
                              await _service.refresh(force: true);
                            }
                          }),
                    child: const Text('保存并同步'),
                  ),
                  OutlinedButton(
                    onPressed: busy || !_service.configured
                        ? null
                        : () => _run(() => _service.refresh(force: true)),
                    child: const Text('立即同步'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(() async {
                            await _service.saveConfig(_service.baseUrl, '');
                            if (mounted) _token.clear();
                          }),
                    child: const Text('停用并清空进度'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              Text(
                '状态：${_service.syncing
                    ? '同步中'
                    : _service.configured
                    ? '已配置（只读）'
                    : '未启用'}',
              ),
              Text('已缓存视频：${_service.videoCount}'),
              Text(
                '最近成功：${_service.lastSuccess?.toLocal().toString().split('.').first ?? '尚未成功同步'}',
              ),
              if (_message != null) Text(_message!),
              if (error != null && error.isNotEmpty)
                Text(
                  '同步错误：$error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const Divider(height: 32),
              const Text(
                '使用说明\n\n'
                '• 只读取 PRM 的进度，不读取或写入 B 站观看历史，也不向 PRM 写入观看记录。\n'
                '• 配置、令牌和缓存仅保存在本机，不随 WebDAV 设置备份同步。\n'
                '• 封面上的 PRM 角标和红线只代表 PRM 数据；无记录不等于未看。\n'
                '• “有分P记录”不代表整部视频看完，不显示整体进度条。\n'
                '• PRM 上游同步可能延迟；播放后不会在本机自行增加已看标记。\n'
                '• “立即同步”使用已保存配置；修改地址或令牌后请先“保存并同步”。\n'
                '• 停用将清空本机令牌和进度，不删除 PRM 服务端数据。',
              ),
            ],
          );
        },
      ),
    ),
  );
}
