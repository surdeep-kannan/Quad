import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/context_x.dart';

/// Post and comment text with tappable @mentions, #tags and links, collapsed
/// to [maxLines] with a "more" toggle.
class RichBody extends StatefulWidget {
  const RichBody(this.text, {super.key, this.style, this.maxLines, this.expandable = true});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final bool expandable;

  @override
  State<RichBody> createState() => _RichBodyState();
}

class _RichBodyState extends State<RichBody> {
  static final _pattern = RegExp(
    r'(https?:\/\/[^\s]+)|(@[a-z0-9_.]{3,24})|(#[a-zA-Z][a-zA-Z0-9_-]{1,39})',
    caseSensitive: false,
  );

  final _recognizers = <TapGestureRecognizer>[];
  bool _expanded = false;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  List<InlineSpan> _spans(BuildContext context, TextStyle base) {
    _disposeRecognizers();
    final c = context.colors;
    final linkStyle = base.copyWith(color: c.accentInk, fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _pattern.allMatches(widget.text)) {
      if (match.start > index) spans.add(TextSpan(text: widget.text.substring(index, match.start)));
      final value = match.group(0)!;
      if (match.group(1) != null) {
        final trimmed = value.replaceAll(RegExp(r'[).,!?]+$'), '');
        spans.add(TextSpan(
          text: trimmed,
          style: linkStyle.copyWith(decoration: TextDecoration.underline, decorationColor: c.accentInk),
          recognizer: _tap(() => launchUrl(Uri.parse(trimmed), mode: LaunchMode.externalApplication)),
        ));
        if (trimmed.length < value.length) spans.add(TextSpan(text: value.substring(trimmed.length)));
      } else if (match.group(2) != null) {
        final username = value.substring(1).toLowerCase().replaceAll(RegExp(r'\.+$'), '');
        spans.add(TextSpan(text: value, style: linkStyle, recognizer: _tap(() => context.push('/u/$username'))));
      } else {
        spans.add(TextSpan(
          text: value,
          style: linkStyle,
          recognizer: _tap(() => context.push('/search?q=${Uri.encodeComponent(value.substring(1))}')),
        ));
      }
      index = match.end;
    }
    if (index < widget.text.length) spans.add(TextSpan(text: widget.text.substring(index)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? context.text.bodyMedium!;
    final spans = _spans(context, base);
    final maxLines = _expanded ? null : widget.maxLines;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rich = TextSpan(style: base, children: spans);
        var overflows = false;
        if (widget.maxLines != null && widget.expandable && !_expanded) {
          final painter = TextPainter(
            text: rich,
            maxLines: widget.maxLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          overflows = painter.didExceedMaxLines;
          painter.dispose();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(rich, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
            if (overflows)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = true),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Show more', style: base.copyWith(color: context.colors.inkMuted, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        );
      },
    );
  }
}
