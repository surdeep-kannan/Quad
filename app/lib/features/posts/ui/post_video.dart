import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../core/data/refs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_image.dart';

/// A video inside a post. In feeds it loads only when tapped, so scrolling
/// stays light; on the post page it starts playing right away.
class PostVideo extends StatefulWidget {
  const PostVideo({super.key, required this.media, this.autoplay = false, this.fullHeight = false});

  final MediaItem media;
  final bool autoplay;

  /// Show tall (9:16) videos uncropped, as on the post page. Feeds crop to 4:5.
  final bool fullHeight;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _load(play: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pause when another screen covers this one.
    if (!TickerMode.valuesOf(context).enabled) _controller?.pause();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load({required bool play}) async {
    if (_controller != null) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
    setState(() {
      _controller = controller;
      _failed = false;
    });
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (play && mounted && TickerMode.valuesOf(context).enabled) await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) setState(() {});
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null || _failed) {
      _controller?.dispose();
      _controller = null;
      _load(play: true);
      return;
    }
    if (!controller.value.isInitialized) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final natural = ready ? controller.value.aspectRatio : (widget.media.aspectRatio ?? 9 / 16);
    final aspect = natural.clamp(widget.fullHeight ? 9 / 16 : 4 / 5, 16 / 9);

    final Widget overlay;
    if (_failed) {
      overlay = const Center(child: _Badge(icon: AppIcons.warning, size: 56));
    } else if (controller == null) {
      overlay = const Center(child: _Badge(icon: AppIcons.play, size: 56));
    } else if (!ready) {
      overlay = const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2));
    } else {
      overlay = ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) =>
            value.isPlaying ? const SizedBox.shrink() : const Center(child: _Badge(icon: AppIcons.play, size: 56)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: AspectRatio(
        aspectRatio: aspect,
        child: GestureDetector(
          onTap: _toggle,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  )
                else if (widget.media.thumbnailUrl != null)
                  AppImage(widget.media.thumbnailUrl!, placeholderColor: Colors.black),
                overlay,
                if (ready)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => controller.setVolume(controller.value.volume > 0 ? 0 : 1)),
                      child: _Badge(
                        icon: controller.value.volume > 0 ? AppIcons.volumeOn : AppIcons.volumeOff,
                        size: 30,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}
