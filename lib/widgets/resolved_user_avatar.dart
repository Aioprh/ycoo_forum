import 'package:flutter/material.dart';

import '../services/comment_profile_resolver.dart';
import '../services/profile_service.dart';

/// Loads the real Discuz avatar from the user's profile instead of trusting
/// normalized post HTML, which may have stripped the original avatar node.
class ResolvedUserAvatar extends StatefulWidget {
  final int uid;
  final String username;
  final double radius;
  final VoidCallback? onTap;

  const ResolvedUserAvatar({
    super.key,
    required this.uid,
    required this.username,
    this.radius = 18,
    this.onTap,
  });

  @override
  State<ResolvedUserAvatar> createState() => _ResolvedUserAvatarState();
}

class _ResolvedUserAvatarState extends State<ResolvedUserAvatar> {
  ProfileData? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ResolvedUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.username != widget.username) _load();
  }

  Future<void> _load() async {
    // 没有 UID 且没有用户名就是论坛匿名用户，不要尝试解析用户资料，
    // 也不要显示“?”，统一使用匿名用户头像。
    if (widget.uid <= 0 && widget.username.trim().isEmpty) return;
    final suppliedUid = widget.uid;
    try {
      var uid = suppliedUid;
      if (uid <= 0 && widget.username.trim().isNotEmpty) {
        uid = await CommentProfileResolver.instance.resolveUid(widget.username) ?? 0;
      }
      if (uid <= 0) return;
      final profile = await ProfileService.instance.fetchProfile(
        uid,
        fallbackUsername: widget.username,
      );
      if (mounted) setState(() => _profile = profile);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final name = _profile?.username.trim().isNotEmpty == true
        ? _profile!.username
        : widget.username.trim();
    final avatar = _profile?.avatar ?? '';
    final anonymous = widget.uid <= 0 && widget.username.trim().isEmpty && avatar.isEmpty;
    final child = CircleAvatar(
      radius: widget.radius,
      backgroundColor: s.secondaryContainer,
      backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
      child: avatar.isEmpty
          ? Icon(
              anonymous ? Icons.person_outline_rounded : Icons.person_rounded,
              size: widget.radius * 1.05,
              color: s.onSecondaryContainer,
            )
          : null,
    );
    if (widget.onTap == null) return child;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(widget.radius + 4),
      child: child,
    );
  }
}
