import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/states.dart';
import '../providers.dart';

/// Explains exactly how college scores are calculated. The weights come from
/// the database, so this page is always in sync with the real formula.
class RankingMethodScreen extends ConsumerWidget {
  const RankingMethodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pillars = ref.watch(rankingPillarsProvider);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('How rankings work'),
      ),
      body: pillars.when(
        loading: () => const CenteredLoader(),
        error: (e, _) => ErrorState(error: e),
        data: (list) => ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            Text('Transparent by design', style: context.text.displaySmall),
            const SizedBox(height: Space.md),
            Text(
              'Quad ranks colleges only by what their students do on Quad. It isn\'t an academic ranking and doesn\'t use '
              'placement, fees or exam data. Every college is scored on the same six pillars:',
              style: context.text.bodyLarge!.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: Space.xl),
            for (final p in list)
              Container(
                margin: const EdgeInsets.only(bottom: Space.md),
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.line)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${(p.weight * 100).round()}%', style: context.text.headlineMedium!.copyWith(color: c.accent)),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label, style: context.text.titleMedium),
                          const SizedBox(height: 4),
                          Text(p.description, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.lg),
            Text('The formula', style: context.text.headlineSmall),
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
              child: Text(
                'pillar = ln(1 + value) / ln(1 + best college\'s value)\n'
                'engagement = active students / students\n'
                'score = 100 × Σ (weight × pillar)',
                style: context.text.bodyMedium!.copyWith(fontFamily: 'monospace', height: 1.6),
              ),
            ),
            const SizedBox(height: Space.md),
            Text(
              'Log scaling stops one very large college from flattening everyone else. Colleges with no students on Quad '
              'aren\'t ranked, and colleges with fewer than 10 students are marked "limited data". Scores refresh every hour.',
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
