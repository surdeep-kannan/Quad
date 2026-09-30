import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../communities/data/community.dart';

/// Sits at the top of a room: drop into its voice or video call.
class RoomVoiceBar extends StatelessWidget {
  const RoomVoiceBar({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 8, 10, 8),
      decoration: BoxDecoration(color: c.surfaceMuted, border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Icon(AppIcons.waveform, size: 18, color: c.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              room.topic ?? 'Voice and video are open. Drop in.',
              style: context.text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppButton(
            label: 'Voice',
            icon: AppIcons.headphones,
            size: ButtonSize.small,
            variant: ButtonVariant.secondary,
            onPressed: () => context.push('/voice/${room.id}'),
          ),
          const SizedBox(width: 6),
          AppButton(
            label: 'Video',
            icon: AppIcons.videoCall,
            size: ButtonSize.small,
            onPressed: () => context.push('/voice/${room.id}?video=1'),
          ),
        ],
      ),
    );
  }
}
