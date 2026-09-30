import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icons.dart';
import 'colleges_view.dart';

class CollegesScreen extends StatelessWidget {
  const CollegesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Colleges & rankings'),
      ),
      body: const CollegeLeaderboardView(),
    );
  }
}
