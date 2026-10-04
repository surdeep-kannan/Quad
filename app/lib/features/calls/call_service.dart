import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/realtime.dart';
import '../../core/data/refs.dart';
import '../../core/data/supabase_providers.dart';
import '../../core/utils/errors.dart';
import '../../core/widgets/sheets.dart';
import '../chat/data/chat_models.dart';
import '../chat/data/chat_repository.dart';

/// A call ringing for the signed-in student, from the inbox channel.
final incomingCallProvider = NotifierProvider<IncomingCall, Call?>(IncomingCall.new);

class IncomingCall extends Notifier<Call?> {
  @override
  Call? build() {
    final inbox = ref.watch(inboxRealtimeProvider);
    final me = ref.watch(currentUserIdProvider);
    final subscription = inbox?.events.listen((event) {
      if (event is! CallChanged) return;
      final call = Call.fromJson(event.row);
      if (event.isNew && call.status == 'ringing' && call.startedBy != me) {
        state = call;
      } else if (state?.id == call.id && call.status != 'ringing') {
        state = null;
      }
    });
    ref.onDispose(() => unawaited(subscription?.cancel()));
    return null;
  }

  void clear() => state = null;
}

/// Starts a call in a conversation and opens the call screen.
Future<void> startCall(BuildContext context, WidgetRef ref, String conversationId, {required bool video}) async {
  try {
    final callId = await ref.read(chatRepositoryProvider).startCall(conversationId, video: video);
    if (context.mounted) await context.push('/call/$callId?outgoing=1');
  } catch (error) {
    if (context.mounted) showToast(context, friendlyError(error), error: true);
  }
}

/// A live audio/video session on LiveKit, for a call ([callId]) or a
/// community room ([roomId]). The database hands out the access token, so
/// only people in the conversation or community can join.
class CallSession extends ChangeNotifier {
  CallSession({required ChatRepository repo, this.callId, this.roomId, required this.video}) : _repo = repo;

  final ChatRepository _repo;
  final String? callId;
  final String? roomId;
  final bool video;

  final lk.Room room = lk.Room(
    roomOptions: const lk.RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      defaultCameraCaptureOptions: lk.CameraCaptureOptions(params: lk.VideoParametersPresets.h540_169),
    ),
  );
  lk.EventsListener<lk.RoomEvent>? _events;

  bool micOn = true;
  late bool cameraOn = video;
  late bool speakerOn = video;
  bool joined = false;
  bool disposed = false;

  /// Couldn't join at all.
  String? error;

  /// Joined, but something needs attention (such as a blocked microphone).
  String? warning;

  Future<void> join() async {
    try {
      final grant = await _repo.callToken(callId: callId, roomId: roomId);
      if (disposed) return;
      _events = room.createListener()..listen((_) => _notify());
      room.addListener(_notify);
      await room.connect(grant.url, grant.token);
      if (disposed) {
        await room.disconnect();
        return;
      }
      joined = true;
      // Browsers only play call audio after a tap; joining came from one.
      if (kIsWeb && !room.canPlaybackAudio) await room.startAudio();
    } on PostgrestException catch (e) {
      error = friendlyError(e);
      _notify();
      return;
    } catch (e) {
      debugPrint('Call connect failed: $e');
      error = 'Couldn\'t connect the call. Check your connection.';
      _notify();
      return;
    }
    _notify();

    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (_) {
      micOn = false;
      warning = 'Allow microphone access so others can hear you.';
    }
    if (video) {
      try {
        await room.localParticipant?.setCameraEnabled(true);
      } catch (_) {
        cameraOn = false;
        warning ??= 'Allow camera access so others can see you.';
      }
    }
    if (!kIsWeb) unawaited(lk.Hardware.instance.setSpeakerphoneOn(speakerOn).catchError((_) {}));
    _notify();
  }

  List<lk.RemoteParticipant> get remote => room.remoteParticipants.values.toList();

  bool get anyoneConnected => room.remoteParticipants.isNotEmpty;

  lk.LocalParticipant? get local => room.localParticipant;

  Future<void> toggleMic() async {
    micOn = !micOn;
    _notify();
    try {
      await room.localParticipant?.setMicrophoneEnabled(micOn);
      if (micOn) warning = null;
    } catch (_) {
      micOn = false;
      warning = 'Allow microphone access so others can hear you.';
    }
    _notify();
  }

  Future<void> toggleCamera() async {
    cameraOn = !cameraOn;
    _notify();
    try {
      await room.localParticipant?.setCameraEnabled(cameraOn);
    } catch (_) {
      cameraOn = false;
      warning = 'Allow camera access so others can see you.';
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final track = room.localParticipant?.videoTrackPublications.firstOrNull?.track;
    final options = track?.currentOptions;
    if (track != null && options is lk.CameraCaptureOptions) {
      await track.setCameraPosition(options.cameraPosition.switched());
    }
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    _notify();
    await lk.Hardware.instance.setSpeakerphoneOn(speakerOn).catchError((_) {});
  }

  Future<void> leave() async {
    if (disposed) return;
    disposed = true;
    room.removeListener(_notify);
    await _events?.dispose();
    await room.disconnect();
    await room.dispose();
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }
}

/// How a participant appears: their profile when we know them, otherwise
/// the name and photo carried in their call token.
UserRef participantRef(lk.Participant participant, Map<String, UserRef> known) {
  final person = known[participant.identity];
  if (person != null) return person;
  Map<String, dynamic>? meta;
  try {
    meta = jsonDecode(participant.metadata ?? '') as Map<String, dynamic>?;
  } catch (_) {}
  return UserRef(
    id: participant.identity,
    username: meta?['username'] as String? ?? '',
    fullName: participant.name.isEmpty ? 'Guest' : participant.name,
    avatarUrl: meta?['avatar_url'] as String?,
    isAnonymous: participant.identity.startsWith('anon-'),
  );
}

/// The participant's camera, when it's on and we're receiving it.
lk.VideoTrack? cameraOf(lk.Participant participant) {
  for (final publication in participant.videoTrackPublications) {
    final track = publication.track;
    if (track != null && !publication.muted) return track as lk.VideoTrack;
  }
  return null;
}
