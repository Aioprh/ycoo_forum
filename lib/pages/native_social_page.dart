import 'package:flutter/material.dart';

import '../services/social_service.dart';
import '../utils/forum_text.dart';
import '../widgets/native_icon_style.dart';
import 'native_profile_page.dart';

class NativeSocialPage extends StatefulWidget {
  const NativeSocialPage({super.key});

  @override
  State<NativeSocialPage> createState() => _NativeSocialPageState();
}

enum _SocialTab { friends, following, followers }

class _NativeSocialPageState extends State<NativeSocialPage> {
  _SocialTab _tab = _SocialTab.friends;
  late Future<List<SocialUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SocialUser>> _load() {
    switch (_tab) {
      case _SocialTab.friends:
        return SocialService.instance.fetchFriends();
      case _SocialTab.following:
        return SocialService.instance.fetchFollowing();
      case _SocialTab.followers:
        return SocialService.instance.fetchFollowers();
    }
  }

  void _select(_SocialTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _future = _load();
    });
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  String get _tabTitle => switch (_tab) {
        _SocialTab.friends => '好友',
        _SocialTab.following => '关注',
        _SocialTab.followers => '粉丝',
      };

  String get _emptyText => switch (_tab) {
        _SocialTab.friends => '你添加的好友会显示在这里',
        _SocialTab.following => '你关注的用户会显示在这里',
        _SocialTab.followers => '关注你的用户会显示在这里',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('好友 / 关注'),
        actions: [
          IconButton(onPressed: _refresh, tooltip: '刷新', icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  _tabButton(_SocialTab.friends, '好友', Icons.people_alt_rounded),
                  _tabButton(_SocialTab.following, '关注', Icons.person_add_alt_1_rounded),
                  _tabButton(_SocialTab.followers, '粉丝', Icons.favorite_rounded),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SocialUser>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) {
                  final message = snapshot.error.toString().replaceFirst('Exception: ', '');
                  return _ErrorState(message: forumText(message), onRetry: _refresh);
                }
                final users = snapshot.data ?? const <SocialUser>[];
                if (users.isEmpty) return _EmptyState(title: '暂无$_tabTitle', subtitle: _emptyText);
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _UserCard(user: users[index], tab: _tab, onChanged: _refresh),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(_SocialTab tab, String label, IconData icon) {
    final selected = _tab == tab;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => _select(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: selected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NativeFeatureIcon(icon: icon, size: NativeIconStyle.smallSize, selected: selected),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final SocialUser user;
  final _SocialTab tab;
  final Future<void> Function() onChanged;

  const _UserCard({required this.user, required this.tab, required this.onChanged});

  Future<void> _toggle(BuildContext context) async {
    final follow = tab == _SocialTab.followers;
    final result = await SocialService.instance.toggleFollow(uid: user.uid, follow: follow);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(forumText(result ?? (follow ? '已关注' : '已取消关注'))), behavior: SnackBarBehavior.floating));
    if (result == null) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = forumText(user.name);
    final subtitle = forumText(user.subtitle);
    final first = name.isEmpty ? '用' : name.characters.first;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: user.uid > 0 ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NativeProfilePage(uid: user.uid, username: name))) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: user.avatar.isEmpty ? null : NetworkImage(user.avatar),
                child: user.avatar.isEmpty ? Text(first, style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    _SocialMetaText(text: subtitle.isEmpty ? 'UID ${user.uid}' : subtitle),
                  ],
                ),
              ),
              if (tab != _SocialTab.friends)
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: () => _toggle(context),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 11), visualDensity: VisualDensity.compact),
                    child: Text(tab == _SocialTab.followers ? '关注' : '取消关注'),
                  ),
                )
              else
                NativeFeatureIcon(icon: Icons.chevron_right_rounded, size: NativeIconStyle.mediumSize),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialMetaText extends StatelessWidget {
  final String text;
  const _SocialMetaText({required this.text});

  @override
  Widget build(BuildContext context) {
    final value = forumText(text);
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final hasNote = normalized.contains('备注');
    final hasStar = normalized.contains('星标');

    if (!hasNote && !hasStar) {
      return Text(normalized, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.3, color: Theme.of(context).colorScheme.onSurfaceVariant));
    }

    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        if (hasNote) _MetaChip(icon: Icons.sticky_note_2_outlined, label: '备注', color: scheme.onSurfaceVariant),
        if (hasStar) _MetaChip(icon: Icons.star_border_rounded, label: '星标', color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MetaChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [NativeFeatureIcon(icon: icon, size: 15), const SizedBox(width: 3), Text(label, style: TextStyle(fontSize: 11, color: color))]);
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 68, height: 68, decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle), child: NativeFeatureIcon(icon: Icons.people_alt_rounded, size: 32, selected: true)), const SizedBox(height: 14), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))])));
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [NativeFeatureIcon(icon: Icons.cloud_off_rounded, size: 48), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('重试'))])));
  }
}
