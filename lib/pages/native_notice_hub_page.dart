import 'package:flutter/material.dart';

import 'member_feature_page.dart';
import 'native_message_list_page.dart';
import 'native_social_page.dart';

class NativeNoticeHubPage extends StatelessWidget {
  const NativeNoticeHubPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _item({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 104,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(color: color.withValues(alpha: .18), shape: BoxShape.circle),
                  child: Icon(icon, size: 31, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('消息提醒')),
      body: ListView(
        children: [
          _item(
            context: context,
            icon: Icons.chat_bubble_rounded,
            color: Colors.lightBlue,
            title: '我的消息',
            subtitle: '站内私信',
            onTap: () => _open(context, const NativeMessageListPage()),
          ),
          const Divider(height: 1),
          _item(
            context: context,
            icon: Icons.people_alt_rounded,
            color: Colors.redAccent,
            title: '我的粉丝',
            subtitle: '关注我的用户',
            onTap: () => _open(context, const NativeSocialPage()),
          ),
          const Divider(height: 1),
          _item(
            context: context,
            icon: Icons.forum_rounded,
            color: Colors.lightGreen,
            title: '我的帖子',
            subtitle: '我发布的主题和回帖',
            onTap: () => _open(context, const MemberFeaturePage(title: '我的主题', path: 'home.php?mod=space&do=thread&view=me&mobile=2', type: MemberFeatureType.threads)),
          ),
          const Divider(height: 1),
          _item(
            context: context,
            icon: Icons.send_rounded,
            color: Colors.amber,
            title: '坛友互动',
            subtitle: '回复、评论、点赞和关注',
            onTap: () => _open(context, const MemberFeaturePage(title: '坛友互动', path: 'home.php?mod=space&do=notice&view=interactive&mobile=2', type: MemberFeatureType.notices)),
          ),
          const Divider(height: 1),
          _item(
            context: context,
            icon: Icons.smart_toy_rounded,
            color: Colors.redAccent,
            title: '系统提醒',
            subtitle: '系统消息和账号提醒',
            onTap: () => _open(context, const MemberFeaturePage(title: '系统提醒', path: 'home.php?mod=space&do=notice&view=system&mobile=2', type: MemberFeatureType.notices)),
          ),
          const Divider(height: 1),
          _item(
            context: context,
            icon: Icons.notifications_active_rounded,
            color: Colors.blueAccent,
            title: '应用提醒',
            subtitle: '应用和社区服务提醒',
            onTap: () => _open(context, const MemberFeaturePage(title: '应用提醒', path: 'home.php?mod=space&do=notice&view=app&mobile=2', type: MemberFeatureType.notices)),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
