import 'package:flutter/material.dart';
import 'package:raze_store/app/theme/theme.dart';

/// A compact, card-backed drawer for secondary controls.
///
/// Drawers start closed so settings pages stay easy to scan, even when a
/// section contains several controls.
class AppExpansionCard extends StatelessWidget {
  const AppExpansionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: false,
        tilePadding: const EdgeInsets.only(
          left: AppSpacing.sm,
          right: AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: SizedBox.square(
          dimension: AppSize.compactControl,
          child: Icon(icon, size: 19, color: scheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [child],
      ),
    );
  }
}
