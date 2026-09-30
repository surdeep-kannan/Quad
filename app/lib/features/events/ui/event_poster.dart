import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/json.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/event.dart';

enum PosterStyle {
  bold('Bold'),
  grid('Grid'),
  ticket('Ticket'),
  minimal('Minimal');

  const PosterStyle(this.label);

  final String label;

  static PosterStyle from(Object? key) => values.where((s) => s.name == key).firstOrNull ?? PosterStyle.bold;
}

/// An event's poster: the uploaded image, or a generated typographic poster
/// built from the event itself (so every event looks designed).
class EventPoster extends StatelessWidget {
  const EventPoster({
    super.key,
    required this.title,
    required this.startsAt,
    required this.category,
    this.venue,
    this.imageUrl,
    this.theme,
    this.radius = 16,
    this.aspectRatio = 4 / 5,
  });

  factory EventPoster.of(CampusEvent event, {double radius = 16, double aspectRatio = 4 / 5}) => EventPoster(
        title: event.title,
        startsAt: event.startsAt,
        category: event.category,
        venue: event.where,
        imageUrl: event.posterUrl,
        theme: event.posterTheme,
        radius: radius,
        aspectRatio: aspectRatio,
      );

  final String title;
  final DateTime startsAt;
  final String category;
  final String? venue;
  final String? imageUrl;
  final Json? theme;
  final double radius;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final child = imageUrl != null
        ? AppImage(imageUrl!, semanticLabel: 'Poster for $title')
        : Semantics(
            label: 'Poster for $title',
            image: true,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 400,
                height: 400 / aspectRatio,
                child: _GeneratedPoster(
                  style: PosterStyle.from(theme?['style']),
                  color: Palette.at(intOf(theme?['color'])),
                  title: title,
                  startsAt: startsAt.toLocal(),
                  category: EventCategories.single(category),
                  venue: venue,
                ),
              ),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(aspectRatio: aspectRatio, child: child),
    );
  }
}

class _GeneratedPoster extends StatelessWidget {
  const _GeneratedPoster({
    required this.style,
    required this.color,
    required this.title,
    required this.startsAt,
    required this.category,
    this.venue,
  });

  final PosterStyle style;
  final Color color;
  final String title;
  final DateTime startsAt;
  final String category;
  final String? venue;

  TextStyle _display(double size, Color color, {double height = 0.95}) => TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: height,
        letterSpacing: -size * 0.035,
        color: color,
      );

  TextStyle _label(Color color, {double size = 13}) => TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w700,
        fontSize: size,
        letterSpacing: 1.6,
        color: color,
      );

  double get _titleSize {
    final length = title.length;
    if (length <= 14) return 64;
    if (length <= 24) return 54;
    if (length <= 36) return 46;
    return 38;
  }

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(startsAt).toUpperCase();
    final day = DateFormat('d').format(startsAt);
    final month = DateFormat('MMM').format(startsAt).toUpperCase();
    final time = DateFormat('h:mm a').format(startsAt);

    switch (style) {
      case PosterStyle.bold:
        final fg = Palette.foregroundOn(color);
        return ColoredBox(
          color: color,
          child: Stack(
            children: [
              Positioned(right: -90, top: -70, child: _Circle(size: 280, color: fg.withValues(alpha: 0.12))),
              Positioned(left: -60, bottom: 90, child: _Circle(size: 170, color: fg.withValues(alpha: 0.08))),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.toUpperCase(), style: _label(fg.withValues(alpha: 0.85))),
                    const Spacer(),
                    Text(title, style: _display(_titleSize, fg), maxLines: 5, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 22),
                    Container(height: 2, color: fg.withValues(alpha: 0.35)),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            '$weekday $day $month · $time',
                            style: _label(fg, size: 15).copyWith(letterSpacing: 0.4),
                          ),
                        ),
                      ],
                    ),
                    if (venue != null) ...[
                      const SizedBox(height: 4),
                      Text(venue!, style: _label(fg.withValues(alpha: 0.8), size: 13).copyWith(letterSpacing: 0.2), maxLines: 1),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      case PosterStyle.grid:
        const bg = Color(0xFF121216);
        return ColoredBox(
          color: bg,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter(Colors.white.withValues(alpha: 0.07)))),
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 10, color: color)),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 28, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(category.toUpperCase(), style: _label(color)),
                        const Spacer(),
                        Text('$day.${startsAt.month.toString().padLeft(2, '0')}', style: _display(28, Colors.white)),
                      ],
                    ),
                    const Spacer(),
                    Text(title, style: _display(_titleSize * 0.92, Colors.white), maxLines: 5, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 18),
                    Text('$weekday · $time', style: _label(Colors.white70, size: 14)),
                    if (venue != null)
                      Text(venue!.toUpperCase(), style: _label(Colors.white38, size: 12), maxLines: 1),
                  ],
                ),
              ),
            ],
          ),
        );
      case PosterStyle.ticket:
        const paper = Color(0xFFF6F0E4);
        const ink = Color(0xFF1B1A1F);
        return ColoredBox(
          color: paper,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                        child: Text(category.toUpperCase(), style: _label(Palette.foregroundOn(color), size: 11)),
                      ),
                      const Spacer(),
                      Text(title, style: _display(_titleSize * 0.8, ink), maxLines: 6, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 16),
                      Text(time, style: _label(ink, size: 14).copyWith(letterSpacing: 0.4)),
                      if (venue != null)
                        Text(venue!, style: _label(ink.withValues(alpha: 0.6), size: 12).copyWith(letterSpacing: 0.2), maxLines: 2),
                    ],
                  ),
                ),
              ),
              CustomPaint(size: const Size(2, double.infinity), painter: _PerforationPainter(ink.withValues(alpha: 0.35))),
              SizedBox(
                width: 96,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(weekday, style: _label(ink.withValues(alpha: 0.6))),
                    Text(day, style: _display(60, color, height: 1)),
                    Text(month, style: _label(ink)),
                  ],
                ),
              ),
            ],
          ),
        );
      case PosterStyle.minimal:
        final tint = Color.alphaBlend(color.withValues(alpha: 0.16), const Color(0xFFFFFCF7));
        const ink = Color(0xFF17161C);
        return ColoredBox(
          color: tint,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day, style: _display(150, color, height: 0.9)),
                Text('$month · $weekday', style: _label(ink)),
                const Spacer(),
                Text(title, style: _display(_titleSize * 0.78, ink), maxLines: 5, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 14),
                Text(
                  [time, ?venue].join('  ·  '),
                  style: _label(ink.withValues(alpha: 0.65), size: 12).copyWith(letterSpacing: 0.3),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}

class _PerforationPainter extends CustomPainter {
  _PerforationPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double y = 12; y < size.height - 12; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 5), paint);
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter oldDelegate) => oldDelegate.color != color;
}
