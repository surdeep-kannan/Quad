import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/media.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/states.dart';
import '../../communities/data/community.dart';
import '../../communities/providers.dart';
import '../../profile/providers.dart';
import '../data/event.dart';
import '../data/event_repository.dart';
import '../providers.dart';
import 'event_poster.dart';

/// Create or edit an event, including designing its poster.
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({super.key, this.eventId, this.communityId});

  final String? eventId;
  final String? communityId;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _venue = TextEditingController();
  final _address = TextEditingController();
  final _link = TextEditingController();
  final _capacity = TextEditingController();

  String _category = 'workshop';
  String _mode = 'in_person';
  late DateTime _start = _defaultStart();
  Duration _length = const Duration(hours: 2);
  DateTime? _deadline;
  Community? _community;
  bool _membersOnly = false;
  PosterStyle _posterStyle = PosterStyle.bold;
  int _posterColor = 0;
  PickedFile? _posterImage;
  String? _existingPosterUrl;
  bool _loaded = false;
  bool _busy = false;

  bool get _editing => widget.eventId != null;

  static DateTime _defaultStart() {
    final now = DateTime.now().add(const Duration(days: 3));
    return DateTime(now.year, now.month, now.day, 18);
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    if (_editing) {
      _load();
    } else {
      _loaded = true;
      if (widget.communityId != null) {
        final mine = ref.read(myCommunitiesProvider).value ?? const [];
        _community = mine.where((c) => c.id == widget.communityId && c.isMod).firstOrNull;
      }
    }
  }

  Future<void> _load() async {
    final repo = ref.read(eventRepositoryProvider);
    final event = await repo.byId(widget.eventId!);
    if (event == null || !mounted) return;
    final link = await repo.meetingLink(event.id).catchError((_) => null);
    setState(() {
      _title.text = event.title;
      _description.text = event.description ?? '';
      _venue.text = event.venue ?? '';
      _address.text = event.address ?? '';
      _link.text = link ?? '';
      _capacity.text = event.capacity?.toString() ?? '';
      _category = event.category;
      _mode = event.mode;
      _start = event.startsAt.toLocal();
      _length = event.effectiveEnd.difference(event.startsAt);
      _deadline = event.registrationDeadline?.toLocal();
      _membersOnly = event.visibility == 'community';
      _posterStyle = PosterStyle.from(event.posterTheme?['style']);
      _posterColor = (event.posterTheme?['color'] as num?)?.toInt() ?? 0;
      _existingPosterUrl = event.posterUrl;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _venue.dispose();
    _address.dispose();
    _link.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (time == null) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickCommunity() async {
    final mods = (ref.read(myCommunitiesProvider).value ?? const []).where((c) => c.isMod).toList();
    final picked = await showAppSheet<Object>(
      context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Space.lg),
        children: [
          ListTile(
            leading: const Icon(AppIcons.user),
            title: const Text('Just me'),
            subtitle: const Text('A personal event'),
            onTap: () => Navigator.of(sheetContext).pop('none'),
          ),
          for (final community in mods)
            ListTile(
              leading: const Icon(AppIcons.communities),
              title: Text(community.name),
              subtitle: const Text('You moderate this community'),
              onTap: () => Navigator.of(sheetContext).pop(community),
            ),
          if (mods.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text('You can host events for communities you moderate.', style: sheetContext.text.bodySmall),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _community = picked is Community ? picked : null);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      String? posterUrl = _existingPosterUrl;
      if (_posterImage != null) posterUrl = await ref.read(storageRepositoryProvider).uploadMedia(_posterImage!, folder: 'posters');
      final me = ref.read(myProfileProvider).value;
      final capacity = int.tryParse(_capacity.text.trim());
      final fields = {
        'title': _title.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'category': _category,
        'mode': _mode,
        'starts_at': _start.toUtc().toIso8601String(),
        'ends_at': _start.add(_length).toUtc().toIso8601String(),
        'venue': _mode == 'online' || _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        'address': _mode == 'online' || _address.text.trim().isEmpty ? null : _address.text.trim(),
        'meeting_url': _mode == 'in_person' || _link.text.trim().isEmpty ? null : _link.text.trim(),
        'capacity': capacity != null && capacity > 0 ? capacity : null,
        'registration_deadline': _deadline?.toUtc().toIso8601String(),
        'community_id': _community?.id,
        'college_id': _community?.collegeId ?? me?.collegeId,
        'visibility': _community != null && _membersOnly ? 'community' : 'public',
        'poster_url': posterUrl,
        'poster_theme': {'style': _posterStyle.name, 'color': _posterColor},
      };
      final repo = ref.read(eventRepositoryProvider);
      final id = _editing ? widget.eventId! : await repo.create(fields);
      if (_editing) {
        await repo.update(id, fields);
        ref.invalidate(eventProvider(id));
      }
      ref.invalidate(hostingEventsProvider);
      ref.invalidate(discoverEventsProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (_editing) {
        context.pop();
      } else {
        context.pushReplacement('/event/$id');
      }
      showToast(context, _editing ? 'Event updated' : 'Event published');
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelEvent() async {
    final ok = await confirm(
      context,
      title: 'Cancel this event?',
      message: 'Attendees will see it as cancelled. This can\'t be undone.',
      confirmLabel: 'Cancel event',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(eventRepositoryProvider).cancel(widget.eventId!);
      ref.invalidate(eventProvider(widget.eventId!));
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!_loaded) return Scaffold(appBar: AppBar(), body: const CenteredLoader());
    final dateLabel = DateFormat('EEE, d MMM · h:mm a').format(_start);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => context.pop()),
        title: Text(_editing ? 'Edit event' : 'New event'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, 40),
          children: [
            Center(
              child: SizedBox(
                width: 220,
                child: _posterImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.lg),
                        child: AspectRatio(aspectRatio: 4 / 5, child: Image.memory(_posterImage!.bytes, fit: BoxFit.cover)),
                      )
                    : EventPoster(
                        title: _title.text.trim().isEmpty ? 'Your event title' : _title.text.trim(),
                        startsAt: _start,
                        category: _category,
                        venue: _mode == 'online' ? 'Online' : (_venue.text.trim().isEmpty ? null : _venue.text.trim()),
                        imageUrl: _existingPosterUrl,
                        theme: {'style': _posterStyle.name, 'color': _posterColor},
                      ),
              ),
            ),
            const SizedBox(height: Space.md),
            Center(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final style in PosterStyle.values)
                    PillChip(
                      label: style.label,
                      dense: true,
                      selected: _posterImage == null && _existingPosterUrl == null && _posterStyle == style,
                      onTap: () => setState(() {
                        _posterStyle = style;
                        _posterImage = null;
                        _existingPosterUrl = null;
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < Palette.colors.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _posterColor = i),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Palette.at(i),
                          shape: BoxShape.circle,
                          border: Border.all(color: _posterColor == i ? c.ink : Colors.transparent, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final image = await MediaPicker.image(maxSide: 1600);
                  if (image != null) setState(() => _posterImage = image);
                },
                icon: const Icon(AppIcons.image, size: 18),
                label: const Text('Upload your own poster'),
              ),
            ),
            const SizedBox(height: Space.lg),
            AppTextField(
              label: 'Event name',
              controller: _title,
              textCapitalization: TextCapitalization.words,
              maxLength: 120,
              validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Give it a name' : null,
            ),
            const SizedBox(height: Space.lg),
            Text('Type', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in EventCategories.all.entries)
                  PillChip(
                    label: EventCategories.single(entry.key),
                    icon: EventCategories.icon(entry.key),
                    dense: true,
                    selected: _category == entry.key,
                    onTap: () => setState(() => _category = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),
            _PickerTile(icon: AppIcons.clock, label: 'Starts', value: dateLabel, onTap: _pickDate),
            const SizedBox(height: Space.sm),
            Text('Length', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, duration) in [
                  ('1 hour', const Duration(hours: 1)),
                  ('2 hours', const Duration(hours: 2)),
                  ('Half day', const Duration(hours: 4)),
                  ('Full day', const Duration(hours: 8)),
                  ('24 hours', const Duration(hours: 24)),
                  ('36 hours', const Duration(hours: 36)),
                ])
                  PillChip(label: label, dense: true, selected: _length == duration, onTap: () => setState(() => _length = duration)),
              ],
            ),
            const SizedBox(height: Space.xl),
            Text('Where', style: context.text.labelMedium!.copyWith(color: c.inkMuted)),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label, icon) in [
                  ('in_person', 'In person', AppIcons.mapPin),
                  ('online', 'Online', AppIcons.monitor),
                  ('hybrid', 'Both', AppIcons.globe),
                ])
                  PillChip(label: label, icon: icon, dense: true, selected: _mode == value, onTap: () => setState(() => _mode = value)),
              ],
            ),
            const SizedBox(height: Space.md),
            if (_mode != 'online') ...[
              AppTextField(label: 'Venue', hint: 'e.g. Seminar Hall 2, CS Block', controller: _venue, onChanged: (_) => setState(() {})),
              const SizedBox(height: Space.md),
              AppTextField(label: 'Address (optional)', controller: _address),
              const SizedBox(height: Space.md),
            ],
            if (_mode != 'in_person')
              AppTextField(
                label: 'Meeting link',
                hint: 'https://meet.google.com/...',
                controller: _link,
                keyboardType: TextInputType.url,
                validator: Validators.url,
                helper: 'Only people who register can see it.',
              ),
            const SizedBox(height: Space.xl),
            AppTextField(
              label: 'Capacity (optional)',
              hint: 'Leave empty for unlimited',
              controller: _capacity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              helper: 'When it fills up, new registrations join a waitlist.',
            ),
            const SizedBox(height: Space.md),
            _PickerTile(
              icon: AppIcons.calendarPlus,
              label: 'Registration closes',
              value: _deadline == null ? 'When the event starts' : DateFormat('EEE, d MMM · h:mm a').format(_deadline!),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _deadline ?? _start.subtract(const Duration(days: 1)),
                  firstDate: DateTime.now(),
                  lastDate: _start,
                );
                if (date != null) setState(() => _deadline = DateTime(date.year, date.month, date.day, 23, 59));
              },
              onClear: _deadline == null ? null : () => setState(() => _deadline = null),
            ),
            const SizedBox(height: Space.xl),
            _PickerTile(
              icon: AppIcons.communities,
              label: 'Host',
              value: _community?.name ?? 'Just me',
              onTap: _pickCommunity,
            ),
            if (_community != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _membersOnly,
                onChanged: (v) => setState(() => _membersOnly = v),
                title: const Text('Members only'),
                subtitle: Text('Only ${_community!.name} members can see and register.'),
              ),
            const SizedBox(height: Space.lg),
            AppTextField(
              label: 'Description',
              hint: 'What will people do, learn or win? Who is it for?',
              controller: _description,
              maxLines: 6,
              maxLength: 5000,
            ),
            const SizedBox(height: Space.xl),
            AppButton(label: _editing ? 'Save changes' : 'Publish event', expand: true, loading: _busy, onPressed: _save),
            if (_editing) ...[
              const SizedBox(height: Space.sm),
              AppButton(label: 'Cancel event', variant: ButtonVariant.danger, expand: true, onPressed: _cancelEvent),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.icon, required this.label, required this.value, required this.onTap, this.onClear});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.md + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md + 2),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.labelSmall!.copyWith(color: c.inkMuted)),
                    const SizedBox(height: 2),
                    Text(value, style: context.text.titleSmall),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(tooltip: 'Clear', icon: const Icon(AppIcons.close, size: 18), onPressed: onClear)
              else
                Icon(AppIcons.forward, size: 18, color: c.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
