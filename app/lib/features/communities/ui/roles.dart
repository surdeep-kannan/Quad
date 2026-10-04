import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../data/community.dart';
import '../data/community_repository.dart';
import '../providers.dart';

/// A role name with its colour, as shown next to members.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.name, required this.color, this.icon});

  final String name;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: color)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Text(
            name,
            style: context.text.labelSmall!.copyWith(
              fontSize: 11,
              color: context.colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The owner crown, or a member's top role (plus how many more they have).
class MemberRoleChips extends StatelessWidget {
  const MemberRoleChips({super.key, required this.member});

  final CommunityMember member;

  @override
  Widget build(BuildContext context) {
    if (member.isOwner) return RoleChip(name: 'Owner', color: context.colors.accent, icon: AppIcons.crown);
    if (member.roles.isEmpty) return const SizedBox.shrink();
    final top = member.roles.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoleChip(name: top.name, color: Palette.at(top.color)),
        if (member.roles.length > 1) ...[
          const SizedBox(width: 4),
          Text('+${member.roles.length - 1}', style: context.text.labelSmall!.copyWith(color: context.colors.inkMuted)),
        ],
      ],
    );
  }
}

/// Every role in the community, highest rank first. People who can manage
/// roles can create, edit, reorder and delete the ones ranked below them.
class RolesTab extends ConsumerWidget {
  const RolesTab({super.key, required this.community});

  final Community community;

  bool _canEdit(CommunityRole role) =>
      community.can(CommunityPermissions.manageRoles) && role.position < community.myRank;

  Future<void> _edit(BuildContext context, WidgetRef ref, [CommunityRole? role]) async {
    final saved = await showAppSheet<bool>(
      context,
      expand: true,
      builder: (_) => RoleEditorSheet(community: community, role: role),
    );
    if (saved ?? false) {
      ref.invalidate(communityRolesProvider(community.id));
      ref.invalidate(communityMembersProvider);
    }
  }

  /// Moves [role] just above (or below) its neighbour in the list.
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    CommunityRole role,
    CommunityRole neighbour, {
    required bool up,
  }) async {
    try {
      await ref
          .read(communityRepositoryProvider)
          .updateRole(
            role.id,
            name: role.name,
            color: role.color,
            permissions: role.permissions,
            position: up ? neighbour.position + 1 : math.max(0, neighbour.position - 1),
          );
      ref.invalidate(communityRolesProvider(community.id));
      ref.invalidate(communityMembersProvider);
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, List<CommunityRole> roles, int index) async {
    final role = roles[index];
    final above = index > 0 ? roles[index - 1] : null;
    final below = index < roles.length - 1 ? roles[index + 1] : null;
    await showActionSheet(
      context,
      title: role.name,
      actions: [
        SheetAction(icon: AppIcons.edit, label: 'Edit role', onTap: () => _edit(context, ref, role)),
        if (above != null && above.position + 1 < community.myRank)
          SheetAction(
            icon: AppIcons.forward,
            label: 'Move above ${above.name}',
            onTap: () => _move(context, ref, role, above, up: true),
          ),
        if (below != null)
          SheetAction(
            icon: AppIcons.down,
            label: 'Move below ${below.name}',
            onTap: () => _move(context, ref, role, below, up: false),
          ),
        SheetAction(
          icon: AppIcons.trash,
          label: 'Delete role',
          destructive: true,
          onTap: () => _delete(context, ref, role),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, CommunityRole role) async {
    final ok = await confirm(
      context,
      title: 'Delete ${role.name}?',
      message: role.membersCount == 0
          ? 'Nobody has this role.'
          : '${plural(role.membersCount, 'person', 'people')} will lose it and its permissions.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(communityRepositoryProvider).deleteRole(role.id);
      ref.invalidate(communityRolesProvider(community.id));
      ref.invalidate(communityMembersProvider);
      if (context.mounted) showToast(context, 'Role deleted');
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(communityRolesProvider(community.id));
    final c = context.colors;
    final canManage = community.can(CommunityPermissions.manageRoles);
    return roles.when(
      loading: () => const ListSkeleton(),
      error: (error, _) =>
          ErrorState(error: error, onRetry: () => ref.invalidate(communityRolesProvider(community.id))),
      data: (list) => ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.sm),
            child: Text(
              'Roles higher in the list outrank the ones below. People can only manage members '
              'and roles ranked below their own top role. The owner outranks everyone.',
              style: context.text.bodySmall,
            ),
          ),
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
              child: AppButton(
                label: 'Create a role',
                icon: AppIcons.plus,
                variant: ButtonVariant.secondary,
                size: ButtonSize.medium,
                onPressed: () => _edit(context, ref),
              ),
            ),
          if (list.isEmpty)
            const EmptyState(
              icon: AppIcons.roles,
              title: 'No roles yet',
              message: 'Create roles like "Event team" or "Room helper" and choose what each can do.',
              compact: true,
            ),
          for (var i = 0; i < list.length; i++)
            ListTile(
              onTap: _canEdit(list[i]) ? () => _actions(context, ref, list, i) : null,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Palette.at(list[i].color).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(AppIcons.shield, size: 19, color: Palette.at(list[i].color)),
              ),
              title: Text(list[i].name, style: context.text.titleSmall),
              subtitle: Text(
                [
                  plural(list[i].membersCount, 'member'),
                  if (list[i].permissions.isEmpty)
                    'no permissions'
                  else if (list[i].permissions.length == CommunityPermissions.all.length)
                    'all permissions'
                  else
                    plural(list[i].permissions.length, 'permission'),
                ].join(' · '),
              ),
              trailing: _canEdit(list[i])
                  ? Icon(AppIcons.moreVertical, size: 18, color: c.inkSubtle)
                  : Icon(AppIcons.lock, size: 15, color: c.inkSubtle),
            ),
        ],
      ),
    );
  }
}

/// Create or edit a role: name, colour and what it can do.
class RoleEditorSheet extends ConsumerStatefulWidget {
  const RoleEditorSheet({super.key, required this.community, this.role});

  final Community community;
  final CommunityRole? role;

  @override
  ConsumerState<RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends ConsumerState<RoleEditorSheet> {
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late int _color = widget.role?.color ?? 6;
  late final Set<String> _permissions = {...?widget.role?.permissions};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final repo = ref.read(communityRepositoryProvider);
    final permissions = [
      for (final p in CommunityPermissions.all)
        if (_permissions.contains(p.$1)) p.$1,
    ];
    try {
      final role = widget.role;
      if (role == null) {
        await repo.createRole(widget.community.id, name: name, color: _color, permissions: permissions);
      } else {
        await repo.updateRole(role.id, name: name, color: _color, permissions: permissions, position: role.position);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = Palette.at(_color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.role == null ? 'New role' : 'Edit role', style: context.text.headlineSmall),
                  ),
                  ListenableBuilder(
                    listenable: _name,
                    builder: (context, _) =>
                        RoleChip(name: _name.text.trim().isEmpty ? 'Role name' : _name.text.trim(), color: color),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              TextField(
                controller: _name,
                maxLength: 30,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'e.g. Event team, Room helper'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Space.sm),
              Text('Colour', style: context.text.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < Palette.colors.length; i++)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _color = i);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == i ? c.ink : Colors.transparent, width: 2),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Palette.colors[i], shape: BoxShape.circle),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.xl),
              Row(
                children: [
                  Expanded(child: Text('Permissions', style: context.text.titleSmall)),
                  TextButton(
                    onPressed: () => setState(() {
                      final grantable = [
                        for (final p in CommunityPermissions.all)
                          if (widget.community.can(p.$1)) p.$1,
                      ];
                      if (grantable.every(_permissions.contains)) {
                        _permissions.removeAll(grantable);
                      } else {
                        _permissions.addAll(grantable);
                      }
                    }),
                    child: const Text('Toggle all'),
                  ),
                ],
              ),
              for (final (key, label, description) in CommunityPermissions.all)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _permissions.contains(key),
                  onChanged: widget.community.can(key)
                      ? (on) => setState(() => on ? _permissions.add(key) : _permissions.remove(key))
                      : null,
                  title: Text(label, style: context.text.titleSmall!.copyWith(fontSize: 15)),
                  subtitle: Text(
                    widget.community.can(key) ? description : '$description You don\'t have this permission.',
                    style: context.text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.lg + context.safePadding.bottom),
          child: AppButton(
            label: widget.role == null ? 'Create role' : 'Save role',
            expand: true,
            loading: _busy,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
        ),
      ],
    );
  }
}

/// Tick the roles a member should have. Roles at or above your own rank are
/// shown but can't be changed.
class MemberRolesSheet extends ConsumerStatefulWidget {
  const MemberRolesSheet({super.key, required this.community, required this.member});

  final Community community;
  final CommunityMember member;

  @override
  ConsumerState<MemberRolesSheet> createState() => _MemberRolesSheetState();
}

class _MemberRolesSheetState extends ConsumerState<MemberRolesSheet> {
  late final Set<String> _selected = {for (final role in widget.member.roles) role.id};
  bool _busy = false;

  bool _editable(CommunityRole role) => role.position < widget.community.myRank;

  Future<void> _save(List<CommunityRole> roles) async {
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).setMemberRoles(widget.community.id, widget.member.user.id, [
        for (final role in roles)
          if (_editable(role) && _selected.contains(role.id)) role.id,
      ]);
      ref.invalidate(communityRolesProvider(widget.community.id));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(communityRolesProvider(widget.community.id));
    final member = widget.member;
    return roles.when(
      loading: () => const CenteredLoader(),
      error: (error, _) => ErrorState(error: error, compact: true),
      data: (list) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Row(
              children: [
                UserAvatar(name: member.user.fullName, url: member.user.avatarUrl, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.user.fullName, style: context.text.titleMedium),
                      Text('Choose their roles', style: context.text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (list.isEmpty)
            const EmptyState(
              icon: AppIcons.roles,
              title: 'No roles yet',
              message: 'Create roles from Manage → Roles first.',
              compact: true,
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final role in list)
                    CheckboxListTile(
                      value: _selected.contains(role.id),
                      onChanged: _editable(role)
                          ? (on) => setState(() => on! ? _selected.add(role.id) : _selected.remove(role.id))
                          : null,
                      controlAffinity: ListTileControlAffinity.trailing,
                      contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                      title: Align(
                        alignment: Alignment.centerLeft,
                        child: RoleChip(name: role.name, color: Palette.at(role.color)),
                      ),
                      subtitle: Text(
                        _editable(role)
                            ? (role.permissions.isEmpty
                                  ? 'No permissions'
                                  : role.permissions.map(CommunityPermissions.label).join(', '))
                            : 'Ranked at or above you',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, Space.lg + context.safePadding.bottom),
            child: AppButton(
              label: 'Save roles',
              expand: true,
              loading: _busy,
              onPressed: list.isEmpty ? null : () => _save(list),
            ),
          ),
        ],
      ),
    );
  }
}
