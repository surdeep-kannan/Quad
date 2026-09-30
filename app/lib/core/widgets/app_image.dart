import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/context_x.dart';
import 'app_icons.dart';

/// Network image with a quiet placeholder and a short fade-in.
class AppImage extends StatelessWidget {
  const AppImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.radius = 0,
    this.placeholderColor,
    this.semanticLabel,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double radius;
  final Color? placeholderColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placeholder = Container(width: width, height: height, color: placeholderColor ?? c.surfaceMuted);
    final image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => Container(
        width: width,
        height: height,
        color: placeholderColor ?? c.surfaceMuted,
        alignment: Alignment.center,
        child: Icon(AppIcons.image, color: c.inkSubtle, size: 22),
      ),
    );
    final labelled = semanticLabel == null ? image : Semantics(image: true, label: semanticLabel, child: image);
    if (radius == 0) return labelled;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: labelled);
  }
}
