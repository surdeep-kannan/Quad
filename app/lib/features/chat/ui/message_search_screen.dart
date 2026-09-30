import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/states.dart';
import '../providers.dart';

class MessageSearchScreen extends ConsumerStatefulWidget {
  const MessageSearchScreen({super.key});

  @override
  ConsumerState<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends ConsumerState<MessageSearchScreen> {
  final _debounce = Debouncer(const Duration(milliseconds: 350));
  String _query = '';

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(messageSearchProvider(_query));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: Space.gutter),
          child: SearchField(
            hint: 'Search all your messages',
            autofocus: true,
            onChanged: (value) => _debounce(() => setState(() => _query = value)),
          ),
        ),
      ),
      body: _query.trim().length < 2
          ? const EmptyState(icon: AppIcons.search, title: 'Find any message', message: 'Search across chats, groups and rooms.')
          : results.when(
              loading: () => const ListSkeleton(),
              error: (error, _) => ErrorState(error: error),
              data: (hits) {
                if (hits.isEmpty) return EmptyState(icon: AppIcons.search, title: 'No messages match "$_query"', compact: true);
                return ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const Divider(indent: 72),
                  itemBuilder: (_, i) {
                    final hit = hits[i];
                    return ListTile(
                      leading: UserAvatar(name: hit.sender.fullName, url: hit.sender.avatarUrl, size: 40),
                      title: Row(
                        children: [
                          Expanded(child: Text(hit.conversationTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text(chatTime(hit.createdAt), style: context.text.bodySmall),
                        ],
                      ),
                      subtitle: Text('${hit.sender.firstName}: ${hit.body}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => context.push('/chat/${hit.conversationId}'),
                    );
                  },
                );
              },
            ),
    );
  }
}
