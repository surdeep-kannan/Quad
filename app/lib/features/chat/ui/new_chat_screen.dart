import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../posts/ui/post_card.dart';
import '../../profile/data/profile.dart';
import '../../profile/providers.dart';
import '../../search/data/search_repository.dart';
import '../data/chat_repository.dart';
import '../providers.dart';

final _peopleSearchProvider = FutureProvider.autoDispose.family<List<Profile>, String>((ref, query) async {
  if (query.trim().isEmpty) return ref.watch(suggestedPeopleProvider.future);
  return ref.watch(searchRepositoryProvider).people(query.trim());
});

/// Start a direct chat, or pick several people to create a group.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _debounce = Debouncer(const Duration(milliseconds: 300));
  final _groupName = TextEditingController();
  String _query = '';
  bool _group = false;
  final Map<String, Profile> _selected = {};
  bool _busy = false;

  @override
  void dispose() {
    _debounce.dispose();
    _groupName.dispose();
    super.dispose();
  }

  Future<void> _open(Profile profile) async {
    if (_group) {
      setState(() => _selected.containsKey(profile.id) ? _selected.remove(profile.id) : _selected[profile.id] = profile);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref.read(chatRepositoryProvider).directWith(profile.id);
      await ref.read(chatListProvider.notifier).refresh();
      if (mounted) context.pushReplacement('/chat/$id');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup() async {
    if (_groupName.text.trim().isEmpty) {
      showToast(context, 'Give the group a name');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref.read(chatRepositoryProvider).createGroup(_groupName.text.trim(), _selected.keys.toList());
      await ref.read(chatListProvider.notifier).refresh();
      if (mounted) context.pushReplacement('/chat/$id');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(_peopleSearchProvider(_query));
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
        title: Text(_group ? 'New group' : 'New chat'),
        actions: [
          if (_group)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AppButton(
                label: 'Create',
                size: ButtonSize.small,
                loading: _busy,
                onPressed: _selected.isEmpty ? null : _createGroup,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: SearchField(
              hint: 'Search people by name or @username',
              autofocus: true,
              onChanged: (value) => _debounce(() => setState(() => _query = value)),
            ),
          ),
          if (_group) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: TextField(controller: _groupName, decoration: const InputDecoration(hintText: 'Group name, e.g. DBMS project')),
            ),
            if (_selected.isNotEmpty)
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 10, Space.gutter, 0),
                  children: [
                    for (final p in _selected.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () => setState(() => _selected.remove(p.id)),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  UserAvatar(name: p.fullName, url: p.avatarUrl, size: 44),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                                      child: Icon(AppIcons.close, size: 12, color: c.inkInverse),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(p.ref.firstName, style: context.text.labelSmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ] else
            ListTile(
              leading: CircleAvatar(backgroundColor: c.surfaceMuted, child: Icon(AppIcons.users, color: c.ink)),
              title: const Text('New group'),
              subtitle: const Text('Project teams, clubs, hostel wing'),
              onTap: () => setState(() => _group = true),
            ),
          const Divider(),
          Expanded(
            child: people.when(
              loading: () => const ListSkeleton(),
              error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(_peopleSearchProvider(_query))),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: AppIcons.search,
                    title: _query.isEmpty ? 'Search for people' : 'No one matches "$_query"',
                    compact: true,
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final profile = list[i];
                    return PersonRow.profile(
                      profile,
                      onTap: _busy ? null : () => _open(profile),
                      trailing: _group
                          ? Icon(
                              _selected.containsKey(profile.id) ? AppIcons.checkCircle : AppIcons.plus,
                              color: _selected.containsKey(profile.id) ? c.accent : c.inkSubtle,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
