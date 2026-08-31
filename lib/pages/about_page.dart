import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _repositoryUrl = 'https://github.com/Aioprh/ycoo_forum';
  static const _downloadBase = 'https://github.com/Aioprh/ycoo_forum';
  static const _latestReleaseApi = 'https://api.github.com/repos/Aioprh/ycoo_forum/releases/latest';
  static const _abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  bool _checking = false;
  bool _hasUpdate = false;
  String? _selfVersion;
  String? _selfBuild;
  String? _latestVersion;
  String? _latestTag;
  List<String> _supportedAbis = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadSelfVersion(), _loadSupportedAbis(), _checkSilently()]);
  }

  Future<void> _loadSelfVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _selfVersion = info.version; // 语义版本名，如 1.0.1
        _selfBuild = info.buildNumber; // 构建号，如 3
      });
    } catch (_) {
      // 读取失败则跳过自版本号，不阻塞静默检查。
    }
  }

  Future<void> _loadSupportedAbis() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      setState(() => _supportedAbis = info.supportedAbis);
    } catch (_) {
      // 非 Android 或读取失败时不设置，回退为默认选择。
    }
  }

  static String _selfFull(String? version, String? build) {
    if (version == null || version.isEmpty) return '';
    return '$version+$build';
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final response = await http.get(
      Uri.parse(_latestReleaseApi),
      headers: const {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // 比较形如 "1.0.1+3" 的版本：先比语义版本名，相同则比构建号。
  int _compareVersions(String a, String b) {
    List<int> parse(String value) {
      final cleaned = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final split = cleaned.split('+');
      final nums = split.first.split('.').map((part) {
        final match = RegExp(r'^\d+').firstMatch(part);
        return int.tryParse(match?.group(0) ?? '0') ?? 0;
      }).take(3).toList();
      while (nums.length < 3) {
        nums.add(0);
      }
      final build = split.length > 1 ? (int.tryParse(split.last) ?? 0) : 0;
      return [...nums, build];
    }

    final left = parse(a);
    final right = parse(b);
    for (var i = 0; i < 4; i++) {
      if (left[i] != right[i]) return left[i].compareTo(right[i]);
    }
    return 0;
  }

  Future<void> _checkSilently() async {
    try {
      final data = await _fetchLatestRelease();
      final tag = (data['tag_name'] as String?)?.trim();
      if (tag == null || tag.isEmpty || !mounted) return;
      final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
      setState(() {
        _latestTag = tag;
        _latestVersion = latest;
        _hasUpdate = _compareVersions(latest, _selfFull(_selfVersion, _selfBuild)) > 0;
      });
    } catch (_) {
      // 网络不可用时不显示红点，避免误报。
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  String get _selfFullVersion => _selfFull(_selfVersion, _selfBuild);

  String _abiLabel(String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return 'arm64-v8a（64 位 ARM · 主流手机）';
      case 'armeabi-v7a':
        return 'armeabi-v7a（32 位 ARM · 较旧手机）';
      case 'x86_64':
        return 'x86_64（模拟器 / x86 设备）';
      default:
        return abi;
    }
  }

  bool _isAbiSupported(String abi) => _supportedAbis.contains(abi);

  String? _preferredAbi() {
    for (final abi in _supportedAbis) {
      if (_abis.contains(abi)) return abi;
    }
    return null;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final data = await _fetchLatestRelease();
      final tag = (data['tag_name'] as String?)?.trim();
      final releaseName = (data['name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) throw const FormatException('版本信息无效');
      final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
      final hasUpdate = _compareVersions(latest, _selfFullVersion) > 0;
      if (!mounted) return;
      setState(() {
        _latestTag = tag;
        _latestVersion = latest;
        _hasUpdate = hasUpdate;
      });
      if (hasUpdate) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('发现新版本'),
            content: Text(
              '${releaseName?.isNotEmpty == true ? releaseName : '源论坛'}\n'
              '最新版本：v$latest\n当前版本：$_selfFullVersion',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('稍后再说')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showArchDialog(latest);
                },
                child: const Text('立即更新'),
              ),
            ],
          ),
        );
      } else {
        _snack('已是最新版本');
      }
    } catch (_) {
      _snack('检查更新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // 选择 CPU 架构，然后在应用内下载并拉起系统安装器。
  Future<void> _showArchDialog(String latest) async {
    var selected = _preferredAbi() ?? 'arm64-v8a';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择安装包'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('请选择与设备 CPU 架构匹配的版本。${_isAbiSupported(selected) ? '已识别到你的设备支持 ${selected}。' : ''}'),
              const SizedBox(height: 8),
              for (final abi in _abis)
                RadioListTile<String>(
                  value: abi,
                  groupValue: selected,
                  onChanged: (v) => setDialogState(() => selected = v!),
                  title: Text(_abiLabel(abi)),
                  subtitle: _isAbiSupported(abi) ? const Text('你的设备支持') : null,
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _downloadAndInstall(selected);
              },
              child: const Text('下载安装'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAndInstall(String abi) async {
    final tag = _latestTag;
    if (tag == null || tag.isEmpty) {
      _snack('版本信息无效');
      return;
    }
    final url = '$_downloadBase/releases/download/${Uri.encodeComponent(tag)}/app-$abi-release.apk';
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('正在下载 $abi …');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (_, value, __) => Text(value, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) => LinearProgressIndicator(value: value),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ycooforum-$abi.apk');
      final request = http.Request('GET', Uri.parse(url));
      final streamed = await request.send().timeout(const Duration(minutes: 10));
      if (streamed.statusCode != 200) throw Exception('HTTP ${streamed.statusCode}');
      final total = streamed.contentLength;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) progress.value = received / total;
      }
      await sink.close();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关闭进度弹窗
      status.value = '下载完成，正在打开安装器…';
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        _snack('无法自动打开安装器，请到系统文件管理中安装 ${file.path}');
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack('下载失败，请检查网络后重试');
    }
  }

  Widget _item({required IconData icon, required String title, required String subtitle, required VoidCallback onTap, Widget? trailing}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: scheme.onPrimaryContainer)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          const SizedBox(height: 12),
          Center(child: Container(width: 76, height: 76, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(24)), child: Icon(Icons.forum_rounded, size: 42, color: scheme.onPrimaryContainer))),
          const SizedBox(height: 14),
          const Center(child: Text('源论坛 YcooForum', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          const SizedBox(height: 26),
          _item(icon: Icons.code_rounded, title: '项目地址', subtitle: 'Aioprh/ycoo_forum · GitHub', onTap: () => _openUrl(_repositoryUrl)),
          const SizedBox(height: 10),
          _item(
            icon: Icons.system_update_alt_rounded,
            title: '检测更新',
            subtitle: _checking ? '正在检查 GitHub Releases…' : (_hasUpdate ? '发现新版本 v$_latestVersion' : '检查是否有新的正式版本'),
            onTap: _checking ? () {} : _checkForUpdates,
            trailing: _checking
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_hasUpdate) Container(width: 9, height: 9, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                    if (_hasUpdate) const SizedBox(width: 10),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
          ),
        ],
      ),
    );
  }
}
