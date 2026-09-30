import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/theme_mode.dart';

class QuadApp extends ConsumerWidget {
  const QuadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Quad',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) {
        // Some dependencies still use the legacy Material library; this maps
        // our theme onto it so their widgets match.
        // ignore: deprecated_member_use
        return MaterialUiCompatibilityBridge(child: child!);
      },
    );
  }
}
