import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import '../data/media.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';
import 'sheets.dart';

/// The frames a photo can be cropped to. Profile photos are always square
/// (shown as a circle).
enum PhotoFrame {
  original('Original', null),
  square('1:1', 1),
  portrait('4:5', 4 / 5),
  landscape('16:9', 16 / 9);

  const PhotoFrame(this.label, this.aspect);

  final String label;
  final double? aspect;
}

/// Lets the student crop, zoom, move and rotate [photo]. Returns the adjusted
/// photo as a JPEG, or null if they cancel. [avatar] uses a round, square
/// frame for profile pictures.
Future<PickedFile?> adjustPhoto(BuildContext context, PickedFile photo, {bool avatar = false, int maxSide = 1600}) {
  return Navigator.of(context, rootNavigator: true).push<PickedFile>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoAdjustScreen(photo: photo, avatar: avatar, maxSide: maxSide),
    ),
  );
}

class PhotoAdjustScreen extends StatefulWidget {
  const PhotoAdjustScreen({super.key, required this.photo, this.avatar = false, this.maxSide = 1600});

  final PickedFile photo;
  final bool avatar;
  final int maxSide;

  @override
  State<PhotoAdjustScreen> createState() => _PhotoAdjustScreenState();
}

class _PhotoAdjustScreenState extends State<PhotoAdjustScreen> {
  final _boundary = GlobalKey();
  final _transform = TransformationController();
  late PhotoFrame _frame = widget.avatar ? PhotoFrame.square : PhotoFrame.original;
  int _turns = 0;
  Size? _source;
  bool _busy = false;

  /// The layout the transform was centred for; recentre when it changes.
  Object? _laidOutFor;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final w = widget.photo.width;
    final h = widget.photo.height;
    if (w != null && h != null && w > 0 && h > 0) {
      setState(() => _source = Size(w.toDouble(), h.toDouble()));
      return;
    }
    final size = await measureImage(widget.photo.bytes);
    if (!mounted) return;
    if (size == null) {
      showToast(context, 'Couldn\'t open that photo. Try another one.', error: true);
      Navigator.of(context).pop();
      return;
    }
    setState(() => _source = Size(size.$1.toDouble(), size.$2.toDouble()));
  }

  /// Source size as currently rotated.
  Size get _oriented => _turns.isOdd ? Size(_source!.height, _source!.width) : _source!;

  double get _frameAspect => _frame.aspect ?? (_oriented.width / _oriented.height);

  Future<void> _done(Size frame, Size laidOut) async {
    setState(() => _busy = true);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // Render at the photo's own resolution (capped), not the screen's.
      final zoom = _transform.value.getMaxScaleOnAxis();
      final visibleSourceWidth = frame.width / (laidOut.width * zoom) * _oriented.width;
      // Never smaller than a sharp avatar, never bigger than [maxSide].
      final targetWidth = visibleSourceWidth.clamp(
        math.min(320.0, widget.maxSide.toDouble()),
        widget.maxSide.toDouble(),
      );
      final image = await boundary.toImage(pixelRatio: targetWidth / frame.width);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      if (raw == null) throw StateError('Could not read the photo');
      final rgba = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      final jpeg = await compute(_encodeJpeg, (rgba, width, height));
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(PickedFile(bytes: jpeg, name: 'photo.jpg', mimeType: 'image/jpeg', width: width, height: height));
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, 'Couldn\'t adjust that photo. Try another one.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(AppIcons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.avatar ? 'Profile photo' : 'Adjust photo', style: const TextStyle(color: Colors.white)),
      ),
      body: source == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white70))
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // The frame: as big as fits, in the chosen shape.
                      var w = box.maxWidth - 32;
                      var h = w / _frameAspect;
                      if (h > box.maxHeight - 32) {
                        h = box.maxHeight - 32;
                        w = h * _frameAspect;
                      }
                      // The photo is laid out to cover the frame; zoom and pan from there.
                      final imageAspect = _oriented.width / _oriented.height;
                      final laidOut = imageAspect > w / h ? Size(h * imageAspect, h) : Size(w, w / imageAspect);
                      final layoutKey = (w, h, laidOut, _turns);
                      if (_laidOutFor != layoutKey) {
                        _laidOutFor = layoutKey;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _transform.value = Matrix4.translationValues(
                            -(laidOut.width - w) / 2,
                            -(laidOut.height - h) / 2,
                            0,
                          );
                        });
                      }
                      return Center(
                        child: SizedBox(
                          width: w,
                          height: h,
                          child: Stack(
                            children: [
                              RepaintBoundary(
                                key: _boundary,
                                child: ClipRect(
                                  child: InteractiveViewer(
                                    transformationController: _transform,
                                    constrained: false,
                                    minScale: 1,
                                    maxScale: 6,
                                    boundaryMargin: EdgeInsets.zero,
                                    child: SizedBox(
                                      width: laidOut.width,
                                      height: laidOut.height,
                                      child: RotatedBox(
                                        quarterTurns: _turns,
                                        child: Image.memory(
                                          widget.photo.bytes,
                                          fit: BoxFit.cover,
                                          filterQuality: FilterQuality.high,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IgnorePointer(
                                child: CustomPaint(
                                  size: Size(w, h),
                                  painter: _FramePainter(circle: widget.avatar),
                                ),
                              ),
                              if (_busy)
                                const Positioned.fill(
                                  child: ColoredBox(
                                    color: Colors.black45,
                                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Text('Pinch to zoom · drag to move', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: Space.md),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Rotate',
                          icon: const Icon(AppIcons.rotate, color: Colors.white),
                          onPressed: _busy ? null : () => setState(() => _turns = (_turns + 1) % 4),
                        ),
                        Expanded(
                          child: widget.avatar
                              ? const SizedBox.shrink()
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final frame in PhotoFrame.values)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: GestureDetector(
                                            onTap: _busy ? null : () => setState(() => _frame = frame),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _frame == frame ? Colors.white : Colors.white.withValues(alpha: 0.14),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                frame.label,
                                                style: TextStyle(
                                                  color: _frame == frame ? Colors.black : Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                        Builder(
                          builder: (context) => FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                            onPressed: _busy
                                ? null
                                : () {
                                    final frameBox = _boundary.currentContext?.size;
                                    final key = _laidOutFor;
                                    if (frameBox == null || key is! (double, double, Size, int)) return;
                                    _done(frameBox, key.$3);
                                  },
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Rule-of-thirds guides, and for profile photos a dimmed area outside the
/// circle that will be visible.
class _FramePainter extends CustomPainter {
  const _FramePainter({required this.circle});

  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (circle) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addOval(rect);
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));
      canvas.drawOval(
        rect.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white70,
      );
    }
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), guide);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }
    if (!circle) {
      canvas.drawRect(
        rect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white54,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.circle != circle;
}

/// Runs off the UI thread on phones (inline on the web).
Uint8List _encodeJpeg((Uint8List, int, int) input) {
  final (rgba, width, height) = input;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 88);
}
