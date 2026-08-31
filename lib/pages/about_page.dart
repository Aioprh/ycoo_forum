import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _version = '1.0.0';
  static const _repositoryUrl = 'https://github.com/Aioprh/ycoo_forum';
  static const _latestReleaseApi = 'https://api.github.com/repos/Aioprh/ycoo_forum/releases/latest';
  static const _latestApkUrl = 'https://github.com/Aioprh/ycoo_forum/releases/latest/download/ycooforum.apk';

  bool _checking = false;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接')),
      );
    }
  }

  int _compareVersions(String a, String b) {
    List<int> parse(String value) {
      final cleaned = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
      return cleaned.split('.').map((part) {
        final match = RegExp(r'^\d+').firstMatch(part);
        return int.tryParse(match?.group(0) ?? '0') ?? 0;
      }).toList();
    }

    final left = parse(a);
    final right = parse(b);
    for (var i = 0; i < 3; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final response = await http.get(
        Uri.parse(_latestReleaseApi),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        throw const FormatException('暂无正式版');
      }
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.trim();
      final releaseUrl = (data['html_url'] as String?)?.trim() ?? _repositoryUrl;
      final releaseName = (data['name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) throw const FormatException('版本信息无效');

      final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
      final comparison = _compareVersions(latest, _version);
      if (!mounted) return;

      if (comparison > 0) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('发现新版本'),
            content: Text('${releaseName?.isNotEmpty == true ? releaseName : '源论坛'}\n最新版本：$latest\n当前版本：$_version'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('稍后再说')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openUrl(_latestApkUrl);
                },
                child: const Text('下载更新'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已是最新版本 v$_version')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is FormatException ? e.message : '检查更新失败，请稍后重试';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Widget _item({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
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
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.forum_rounded, size: 42, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 14),
          const Center(child: Text('源论坛 YcooForum', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
          const SizedBox(height: 5),
          Center(child: Text('版本 v$_version', style: TextStyle(color: scheme.onSurfaceVariant))),
          const SizedBox(height: 26),
          _item(
            icon: Icons.code_rounded,
            title: '项目地址',
            subtitle: 'Aioprh/ycoo_forum · GitHub',
            onTap: () => _openUrl(_repositoryUrl),
          ),
          const SizedBox(height: 10),
          _item(
            icon: Icons.system_update_alt_rounded,
            title: '检查更新',
            subtitle: _checking ? '正在检查 GitHub Releases…' : '检查是否有新的正式版本',
            onTap: _checking ? () {} : _checkForUpdates,
            trailing: _checking
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '源论坛 YcooForum 是面向 ycoo.net 的 Flutter 原生移动端项目。\n\n正式版本、更新说明和 APK 将通过 GitHub Releases 发布。',
                style: TextStyle(height: 1.55, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
