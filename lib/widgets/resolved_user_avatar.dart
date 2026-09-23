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
    final child = CircleAvatar(
      radius: widget.radius,
      backgroundColor: s.secondaryContainer,
      backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
      child: avatar.isEmpty
          ? Text(
              name.isEmpty ? '?' : name.characters.first,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: s.onSecondaryContainer,
                fontSize: widget.radius * .85,
              ),
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
