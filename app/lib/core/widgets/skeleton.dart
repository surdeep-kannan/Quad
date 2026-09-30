import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import '../utils/context_x.dart';

/// Pulses its children gently while content loads. Put a single [Skeleton]
/// around a group of [SkeletonBox]es so they pulse together.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
        child: ExcludeSemantics(child: widget.child),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceSunken,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder shaped like a feed post.
class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key, this.withMedia = false});

  final bool withMedia;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SkeletonBox(height: 36, circle: true),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 120, height: 11),
                  SizedBox(height: 6),
                  SkeletonBox(width: 76, height: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SkeletonBox(width: 240, height: 14),
          const SizedBox(height: 8),
          const SkeletonBox(height: 11),
          const SizedBox(height: 6),
          const SkeletonBox(width: 200, height: 11),
          if (withMedia) ...[
            const SizedBox(height: 12),
            const SkeletonBox(height: 180, radius: Radii.md),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shaped like a list row with an avatar.
class RowSkeleton extends StatelessWidget {
  const RowSkeleton({super.key, this.avatarSize = 44, this.square = false});

  final double avatarSize;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: 10),
      child: Row(
        children: [
          SkeletonBox(width: avatarSize, height: avatarSize, circle: !square, radius: avatarSize * 0.3),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 12),
                SizedBox(height: 7),
                SkeletonBox(width: 210, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Several skeletons in a column, for initial list loads.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.count = 6, this.itemBuilder});

  final int count;
  final Widget Function(int index)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        children: [
          for (var i = 0; i < count; i++) itemBuilder?.call(i) ?? const RowSkeleton(),
        ],
      ),
    );
  }
}
