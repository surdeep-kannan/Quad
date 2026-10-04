import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../../../core/data/realtime.dart';
import '../../../core/data/refs.dart';
import '../../../core/data/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/avatars.dart';
import '../../chat/data/chat_models.dart';
import '../../chat/data/chat_repository.dart';
import '../../communities/providers.dart';
import '../call_service.dart';

/// A 1:1 or group call ([callId]) or a community room's voice/video ([roomId]).
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, this.callId, this.roomId, this.outgoing = false, this.video = false});

  final String? callId;
  final String? roomId;
  final bool outgoing;
  final bool video;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Call? _call;
  Map<String, UserRef> _people = {};
  CallSession? _session;
  bool _ringing = false;
  bool _ended = false;
  Timer? _noAnswer;
  Timer? _clock;
  Duration _elapsed = Duration.zero;
  StreamSubscription<InboxEvent>? _events;

  bool get _isRoom => widget.roomId != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(chatRepositoryProvider);
    if (_isRoom) {
      await _join(video: widget.video);
      return;
    }
    final call = await repo.call(widget.callId!);
    if (call == null || !mounted) return _close();
    final members = await repo.members(call.conversationId);
    if (!mounted) return;
    setState(() {
      _call = call;
      _people = {for (final m in members) m.user.id: m.user};
      _ringing = !widget.outgoing && call.status == 'ringing';
    });
    _events = ref.read(inboxRealtimeProvider)?.events.listen((event) {
      if (event is CallChanged && event.row['id'] == call.id) {
        final status = event.row['status'] as String?;
        if (status == 'ended' || status == 'declined' || status == 'missed') _close();
      }
    });
    if (call.status == 'ended' || call.status == 'missed' || call.status == 'declined') return _close();
    if (!_ringing) {
      await _join(video: call.isVideo);
      if (widget.outgoing) {
        _noAnswer = Timer(const Duration(seconds: 45), () {
          if (!(_session?.anyoneConnected ?? false)) {
            unawaited(repo.updateCall(call.id, 'missed').catchError((_) {}));
            _close();
          }
        });
      }
    }
  }

  Future<void> _join({required bool video}) async {
    final session = CallSession(
      repo: ref.read(chatRepositoryProvider),
      callId: widget.callId,
      roomId: widget.roomId,
      video: video,
    );
    session.addListener(_onSession);
    setState(() => _session = session);
    await session.join();
  }

  void _onSession() {
    final session = _session;
    if (session == null || !mounted) return;
    if (session.anyoneConnected && _clock == null) {
      _noAnswer?.cancel();
      _clock = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _elapsed += const Duration(seconds: 1)),
      );
      final call = _call;
      if (call != null && call.status == 'ringing') {
        unawaited(ref.read(chatRepositoryProvider).updateCall(call.id, 'ongoing').catchError((_) {}));
      }
    }
    setState(() {});
  }

  Future<void> _accept() async {
    final call = _call!;
    ref.read(incomingCallProvider.notifier).clear();
    setState(() => _ringing = false);
    unawaited(ref.read(chatRepositoryProvider).updateCall(call.id, 'ongoing').catchError((_) {}));
    await _join(video: call.isVideo);
  }

  Future<void> _decline() async {
    ref.read(incomingCallProvider.notifier).clear();
    await ref.read(chatRepositoryProvider).updateCall(_call!.id, 'declined').catchError((_) {});
    _close();
  }

  Future<void> _hangUp() async {
    final call = _call;
    final alone = (_session?.remote.length ?? 0) <= 1;
    if (call != null && alone) {
      await ref
          .read(chatRepositoryProvider)
          .updateCall(call.id, _session?.anyoneConnected ?? false ? 'ended' : 'missed')
          .catchError((_) {});
    }
    _close();
  }

  void _close() {
    if (_ended) return;
    _ended = true;
    if (mounted && context.canPop()) context.pop();
  }

  @override
  void dispose() {
    _noAnswer?.cancel();
    _clock?.cancel();
    unawaited(_events?.cancel());
    final session = _session;
    if (session != null) {
      session.removeListener(_onSession);
      unawaited(session.leave());
    }
    super.dispose();
  }

  String get _title {
    if (_isRoom) {
      final room = ref.watch(roomProvider(widget.roomId!)).value;
      return room == null ? 'Room call' : '#${room.name}';
    }
    final me = ref.read(currentUserIdProvider);
    final others = _people.values.where((p) => p.id != me).toList();
    if (others.length == 1) return others.first.fullName;
    return others.map((p) => p.firstName).take(3).join(', ');
  }

  String get _status {
    final session = _session;
    if (_ringing) return _call?.isVideo ?? false ? 'Incoming video call' : 'Incoming voice call';
    if (session?.error != null) return session!.error!;
    if (session == null || !session.joined) return 'Connecting…';
    if (session.anyoneConnected) {
      final m = _elapsed.inMinutes.toString().padLeft(2, '0');
      final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return _isRoom ? '${session.remote.length + 1} here · $m:$s' : '$m:$s';
    }
    return _isRoom ? 'Waiting for others to join' : 'Ringing…';
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final me = ref.watch(currentUserIdProvider);
    final others = _people.values.where((p) => p.id != me).toList();
    final hero = others.isEmpty ? null : others.first;
    final video = session?.video ?? false;
    final remote = session?.remote ?? const <lk.RemoteParticipant>[];
    final top = MediaQuery.paddingOf(context).top;

    final Widget stage;
    if (video && remote.isNotEmpty) {
      stage = Positioned.fill(
        child: _VideoGrid(participants: remote, people: _people),
      );
    } else if (_isRoom && session != null && session.joined) {
      stage = Positioned.fill(
        child: _VoiceGrid(session: session, people: _people, title: _title, status: _status),
      );
    } else {
      stage = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(name: hero?.fullName ?? _title, url: hero?.avatarUrl, size: 112),
            const SizedBox(height: 20),
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 15)),
            if (remote.length > 1) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  for (final participant in remote) AuthorAvatar(user: participantRef(participant, _people), size: 44),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final localTrack = session?.local == null ? null : cameraOf(session!.local!);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      body: Stack(
        children: [
          stage,
          if (video && session != null && !_ringing)
            Positioned(
              right: 16,
              top: top + 16,
              width: 110,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Colors.black,
                  child: session.cameraOn && localTrack != null
                      ? lk.VideoTrackRenderer(
                          localTrack,
                          fit: lk.VideoViewFit.cover,
                          mirrorMode: lk.VideoViewMirrorMode.mirror,
                        )
                      : const Center(child: Icon(AppIcons.videoOff, color: Colors.white54)),
                ),
              ),
            ),
          if (video && remote.isNotEmpty)
            Positioned(
              left: 20,
              top: top + 20,
              child: Text(
                _status,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 8)],
                ),
              ),
            ),
          if (session?.warning != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.paddingOf(context).bottom + 130,
              child: Text(
                session!.warning!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB4A6), fontSize: 13),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
            child: _ringing
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        icon: AppIcons.phoneOff,
                        label: 'Decline',
                        color: const Color(0xFFE5383B),
                        onTap: _decline,
                      ),
                      _RoundButton(
                        icon: AppIcons.phoneFill,
                        label: 'Accept',
                        color: const Color(0xFF22B45E),
                        onTap: _accept,
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        icon: session?.micOn ?? true ? AppIcons.mic : AppIcons.micOff,
                        label: session?.micOn ?? true ? 'Mute' : 'Unmute',
                        active: !(session?.micOn ?? true),
                        onTap: session?.toggleMic,
                      ),
                      if (video) ...[
                        _RoundButton(
                          icon: session?.cameraOn ?? true ? AppIcons.videoCall : AppIcons.videoOff,
                          label: 'Camera',
                          active: !(session?.cameraOn ?? true),
                          onTap: session?.toggleCamera,
                        ),
                        if (!kIsWeb)
                          _RoundButton(icon: AppIcons.flipCamera, label: 'Flip', onTap: session?.switchCamera),
                      ],
                      if (!kIsWeb)
                        _RoundButton(
                          icon: AppIcons.speaker,
                          label: 'Speaker',
                          active: session?.speakerOn ?? false,
                          onTap: session?.toggleSpeaker,
                        ),
                      _RoundButton(
                        icon: AppIcons.phoneOff,
                        label: _isRoom ? 'Leave' : 'End',
                        color: const Color(0xFFE5383B),
                        onTap: _hangUp,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Room voice: everyone's avatar, with a ring around whoever is talking.
class _VoiceGrid extends StatelessWidget {
  const _VoiceGrid({required this.session, required this.people, required this.title, required this.status});

  final CallSession session;
  final Map<String, UserRef> people;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    final everyone = <lk.Participant>[?session.local, ...session.remote];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(status, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 28),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 20,
                  children: [
                    for (final participant in everyone)
                      _VoiceTile(
                        person: participantRef(participant, people),
                        speaking: participant.isSpeaking,
                        muted: participant is lk.LocalParticipant ? !session.micOn : participant.isMuted,
                        isMe: participant is lk.LocalParticipant,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.person, required this.speaking, required this.muted, required this.isMe});

  final UserRef person;
  final bool speaking;
  final bool muted;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: speaking ? const Color(0xFF22B45E) : Colors.transparent, width: 3),
                ),
                child: AuthorAvatar(user: person, size: 64),
              ),
              if (muted)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Color(0xFF2A2A31), shape: BoxShape.circle),
                    child: const Icon(AppIcons.micOff, size: 13, color: Colors.white70),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isMe ? '${person.firstName} (you)' : person.firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VideoGrid extends StatelessWidget {
  const _VideoGrid({required this.participants, required this.people});

  final List<lk.RemoteParticipant> participants;
  final Map<String, UserRef> people;

  @override
  Widget build(BuildContext context) {
    final single = participants.length == 1;
    Widget tile(lk.RemoteParticipant participant) {
      final person = participantRef(participant, people);
      final camera = cameraOf(participant);
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFF1B1B20),
            child: camera != null
                ? lk.VideoTrackRenderer(camera, fit: lk.VideoViewFit.cover)
                : Center(child: AuthorAvatar(user: person, size: 72)),
          ),
          Positioned(
            left: single ? 20 : 10,
            // Full-screen video: keep the name clear of the call buttons.
            bottom: single ? MediaQuery.paddingOf(context).bottom + 140 : 10,
            child: Text(
              person.firstName,
              style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
            ),
          ),
        ],
      );
    }

    if (single) return tile(participants.first);
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 0.75,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 60),
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: [for (final participant in participants) tile(participant)],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.color, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? (active ? Colors.white : Colors.white.withValues(alpha: 0.14)),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 64,
              child: Icon(
                icon,
                color: color == null && active ? Colors.black : Colors.white,
                size: 28,
                semanticLabel: label,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
