import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/data/realtime.dart';
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

class Peer {
  Peer(this.userId, this.connection, this.renderer);

  final String userId;
  final RTCPeerConnection connection;
  final RTCVideoRenderer renderer;
  RTCPeerConnectionState state = RTCPeerConnectionState.RTCPeerConnectionStateNew;
  bool remoteDescriptionSet = false;
  final List<RTCIceCandidate> pendingCandidates = [];
  bool hasVideo = false;
}

/// A live audio/video session between everyone on one realtime topic.
///
/// Peers find each other through presence on a private channel and exchange
/// offers, answers and ICE candidates over broadcast. Each pair connects
/// directly (a mesh), which works well for calls of up to about six people.
class CallSession extends ChangeNotifier {
  CallSession({required SupabaseClient client, required this.topic, required this.video}) : _client = client;

  final SupabaseClient _client;

  /// `call:<call id>` or `voice:<room id>`.
  final String topic;
  final bool video;

  final localRenderer = RTCVideoRenderer();
  final Map<String, Peer> peers = {};
  MediaStream? _localStream;
  RealtimeChannel? _channel;
  bool micOn = true;
  late bool cameraOn = video;
  bool joined = false;
  bool disposed = false;
  String? error;

  String get _me => _client.uid;

  Map<String, dynamic> get _config => {
        'iceServers': [
          {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
          if (Env.turnUrl.isNotEmpty) {'urls': Env.turnUrl, 'username': Env.turnUsername, 'credential': Env.turnCredential},
        ],
        'sdpSemantics': 'unified-plan',
      };

  Future<void> join() async {
    try {
      await localRenderer.initialize();
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
      });
      localRenderer.srcObject = _localStream;
    } catch (e) {
      error = video ? 'Allow camera and microphone access to join.' : 'Allow microphone access to join.';
      notifyListeners();
      return;
    }

    final channel = _client.channel(topic, opts: RealtimeChannelConfig(private: true, key: _me));
    _channel = channel;
    channel
        .onBroadcast(event: 'signal', callback: _onSignal)
        .onPresenceSync((_) => _syncPeers())
        .subscribe((status, err) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await channel.track({'video': video, 'joined_at': DateTime.now().toUtc().toIso8601String()});
            joined = true;
            _notify();
          } else if (status == RealtimeSubscribeStatus.channelError) {
            error = 'Couldn\'t connect the call. Check your connection.';
            _notify();
          }
        });
    _notify();
  }

  List<String> get _present {
    final channel = _channel;
    if (channel == null) return const [];
    return [for (final state in channel.presenceState()) state.key];
  }

  /// Connects to newcomers and drops people who left. The student with the
  /// smaller id sends the offer, so two people never offer at once.
  void _syncPeers() {
    final present = _present.toSet();
    for (final userId in present) {
      if (userId == _me || peers.containsKey(userId)) continue;
      if (_me.compareTo(userId) < 0) unawaited(_connect(userId, offer: true));
    }
    for (final userId in peers.keys.toList()) {
      if (!present.contains(userId)) unawaited(_dropPeer(userId));
    }
    _notify();
  }

  Future<Peer> _connect(String userId, {required bool offer}) async {
    final existing = peers[userId];
    if (existing != null) return existing;
    final connection = await createPeerConnection(_config);
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final peer = Peer(userId, connection, renderer);
    peers[userId] = peer;

    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await connection.addTrack(track, _localStream!);
    }
    connection.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        if (event.track.kind == 'video') peer.hasVideo = true;
        _notify();
      }
    };
    connection.onIceCandidate = (candidate) {
      _send(userId, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    connection.onConnectionState = (state) {
      peer.state = state;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) unawaited(_dropPeer(userId));
      _notify();
    };

    if (offer) {
      final description = await connection.createOffer();
      await connection.setLocalDescription(description);
      _send(userId, {'type': 'offer', 'sdp': description.sdp});
    }
    _notify();
    return peer;
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    if (payload['to'] != _me) return;
    final from = payload['from'] as String?;
    if (from == null) return;
    try {
      switch (payload['type']) {
        case 'offer':
          final peer = await _connect(from, offer: false);
          await peer.connection.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'offer'));
          peer.remoteDescriptionSet = true;
          await _flushCandidates(peer);
          final answer = await peer.connection.createAnswer();
          await peer.connection.setLocalDescription(answer);
          _send(from, {'type': 'answer', 'sdp': answer.sdp});
        case 'answer':
          final peer = peers[from];
          if (peer == null) return;
          await peer.connection.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'answer'));
          peer.remoteDescriptionSet = true;
          await _flushCandidates(peer);
        case 'candidate':
          final candidate = RTCIceCandidate(
            payload['candidate'] as String?,
            payload['sdpMid'] as String?,
            (payload['sdpMLineIndex'] as num?)?.toInt(),
          );
          final peer = peers[from] ?? await _connect(from, offer: false);
          if (peer.remoteDescriptionSet) {
            await peer.connection.addCandidate(candidate);
          } else {
            peer.pendingCandidates.add(candidate);
          }
        case 'bye':
          await _dropPeer(from);
      }
    } catch (e) {
      debugPrint('call signal error: $e');
    }
  }

  Future<void> _flushCandidates(Peer peer) async {
    for (final candidate in peer.pendingCandidates) {
      await peer.connection.addCandidate(candidate);
    }
    peer.pendingCandidates.clear();
  }

  void _send(String to, Map<String, dynamic> payload) {
    unawaited(_channel?.sendBroadcastMessage(event: 'signal', payload: {...payload, 'from': _me, 'to': to}));
  }

  Future<void> _dropPeer(String userId) async {
    final peer = peers.remove(userId);
    if (peer == null) return;
    await peer.connection.close();
    peer.renderer.srcObject = null;
    await peer.renderer.dispose();
    _notify();
  }

  void toggleMic() {
    micOn = !micOn;
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = micOn;
    }
    _notify();
  }

  void toggleCamera() {
    cameraOn = !cameraOn;
    for (final track in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = cameraOn;
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  bool get anyoneConnected => peers.values.any((p) => p.state == RTCPeerConnectionState.RTCPeerConnectionStateConnected);

  int get participantCount => _present.length;

  Future<void> leave() async {
    if (disposed) return;
    disposed = true;
    for (final userId in peers.keys) {
      _send(userId, {'type': 'bye'});
    }
    for (final peer in peers.values) {
      await peer.connection.close();
      await peer.renderer.dispose();
    }
    peers.clear();
    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    localRenderer.srcObject = null;
    await localRenderer.dispose();
    final channel = _channel;
    if (channel != null) {
      await channel.untrack();
      await _client.removeChannel(channel);
    }
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }
}
