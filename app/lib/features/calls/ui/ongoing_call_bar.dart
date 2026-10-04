import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_icons.dart';
import '../active_call.dart';

/// While you're in a call and not looking at it, a bar across the top of every
/// screen shows who you're talking to and takes you back with a tap.
class OngoingCallFrame extends ConsumerWidget {
  const OngoingCallFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(activeCallProvider);
    if (call == null) return child;
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        if (call.ended || call.screenOpen) return child;
        final top = MediaQuery.paddingOf(context).top;
        final color = call.ringing ? const Color(0xFF2E8BFF) : const Color(0xFF17A673);
        return Column(
          children: [
            Material(
              color: color,
              child: InkWell(
                onTap: () => ref.read(routerProvider).push(call.route),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, top + 4, 4, 4),
                  child: Row(
                    children: [
                      Icon(call.video ? AppIcons.videoCall : AppIcons.phoneFill, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: call.title,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: '  ${call.ringing ? 'Tap to answer' : call.status}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        tooltip: call.ringing ? 'Decline' : 'Hang up',
                        icon: const Icon(AppIcons.phoneOff, color: Colors.white, size: 20),
                        onPressed: call.ringing ? call.decline : call.hangUp,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The bar already covers the status bar, so screens below start
            // right under it.
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
            ),
          ],
        );
      },
    );
  }
}
