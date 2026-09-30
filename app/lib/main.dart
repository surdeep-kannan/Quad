import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/data/json.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey);
  if (Env.enableSemantics) SemanticsBinding.instance.ensureSemantics();
  runApp(
    ProviderScope(
      // Retry network hiccups twice; database errors are final.
      retry: (retryCount, error) {
        if (retryCount >= 2 || error is PostgrestException || error is AuthException) return null;
        return Duration(milliseconds: 400 * (retryCount + 1));
      },
      child: const QuadApp(),
    ),
  );
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    const Json example = {'SUPABASE_URL': 'https://<ref>.supabase.co', 'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_...'};
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Quad needs its Supabase config.\n\nRun with:\nflutter run --dart-define-from-file=env/dev.json\n\n'
              'env/dev.json:\n$example',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
