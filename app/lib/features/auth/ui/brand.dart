import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';

/// The Quad wordmark: lowercase, heavy, with the accent dot.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 26, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Quad',
      header: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'quad',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w800,
                fontSize: size,
                height: 1,
                letterSpacing: -size * 0.045,
                color: color ?? c.ink,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: size * 0.06, bottom: size * 0.1),
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
