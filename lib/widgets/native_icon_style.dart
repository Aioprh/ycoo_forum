import 'package:flutter/material.dart';

/// Shared icon language for native member/social pages.
/// Keep icons rounded/outlined, with one consistent size and color treatment.
class NativeIconStyle {
  NativeIconStyle._();

  static const double smallSize = 18;
  static const double mediumSize = 20;
  static const double badgeSize = 40;
  static const double badgeIconSize = 20;
  static const BorderRadius badgeRadius = BorderRadius.all(Radius.circular(14));

  static Color color(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;
  static Color accent(BuildContext context) => Theme.of(context).colorScheme.onPrimaryContainer;

  static Widget badge(BuildContext context, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: badgeRadius,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: badgeIconSize, color: scheme.onPrimaryContainer),
    );
  }
}

class NativeFeatureIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool selected;

  const NativeFeatureIcon({
    super.key,
    required this.icon,
    this.size = NativeIconStyle.smallSize,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      icon,
      size: size,
      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
    );
  }
}
