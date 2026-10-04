import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/realtime.dart';
import '../../core/data/refs.dart';
import '../../core/data/supabase_providers.dart';
import '../chat/data/chat_models.dart';
import '../chat/data/chat_repository.dart';
import '../communities/data/community_repository.dart';
import 'call_service.dart';

/// The call you're in (or being rung for). It lives above the screens, so
/// leaving the call screen keeps the call going; a bar at the top of the app
/// takes you back.
final activeCallProvider = NotifierProvider<ActiveCall, OngoingCall?>(ActiveCall.new);

class ActiveCall extends Notifier<OngoingCall?> {
  @override
  OngoingCall? build() {
    // Signing out ends any call.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != null && next != previous) state?.end();
    });
    return null;
  }

  /// The call for these ids, starting it if it isn't the current one.
  /// Opening a different call hangs up the current one first.
  OngoingCall open({String? callId, String? roomId, bool outgoing = false, bool video = false}) {
    final current = state;
    if (current != null && !current.ended && current.callId == callId && current.roomId == roomId) return current;
    if (current != null && !current.ended) unawaited(current.hangUp());
    final call = OngoingCall._(ref, callId: callId, roomId: roomId, outgoing: outgoing, video: video, onEnded: _ended);
    state = call;
    unawaited(call._start());
    return call;
  }

  void _ended(OngoingCall call) {
    if (state == call) state = null;
  }
}

class OngoingCall extends ChangeNotifier {
  OngoingCall._(
    this._ref, {
    required this.callId,
    required this.roomId,
    required this.outgoing,
    required bool video,
    required void Function(OngoingCall) onEnded,
  }) : _video = video,
       _onEnded = onEnded;

  final Ref _ref;
  final String? callId;
  final String? roomId;
  final bool outgoing;
  final bool _video;
  final void Function(OngoingCall) _onEnded;

  Call? call;
  Map<String, UserRef> people = {};
  CallSession? session;
  String? roomName;
  bool ringing = false;
  bool ended = false;
  Duration elapsed = Duration.zero;

  /// Whether the call screen is showing (the "return to call" bar hides then).
  bool screenOpen = false;

  void setScreenOpen(bool open) {
    if (screenOpen == open) return;
    screenOpen = open;
    _notify();
  }

  Timer? _noAnswer;
  Timer? _clock;
  StreamSubscription<InboxEvent>? _events;

  bool get isRoom => roomId != null;
  bool get video => session?.video ?? call?.isVideo ?? _video;

  /// Where the call screen lives.
  String get route => isRoom ? '/voice/$roomId${_video ? '?video=1' : ''}' : '/call/$callId';

  ChatRepository get _repo => _ref.read(chatRepositoryProvider);

  String get title {
    if (isRoom) return roomName == null ? 'Room call' : '#$roomName';
    final me = _ref.read(currentUserIdProvider);
    final others = people.values.where((p) => p.id != me).toList();
    if (others.isEmpty) return 'Call';
    if (others.length == 1) return others.first.fullName;
    return others.map((p) => p.firstName).take(3).join(', ');
  }

  UserRef? get otherPerson {
    final me = _ref.read(currentUserIdProvider);
    return people.values.where((p) => p.id != me).firstOrNull;
  }

  String get status {
    final session = this.session;
    if (ringing) return video ? 'Incoming video call' : 'Incoming voice call';
    if (session?.error != null) return session!.error!;
    if (session == null || !session.joined) return 'Connecting…';
    if (session.anyoneConnected) {
      final m = elapsed.inMinutes.toString().padLeft(2, '0');
      final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return isRoom ? '${session.remote.length + 1} here · $m:$s' : '$m:$s';
    }
    return isRoom ? 'Waiting for others to join' : 'Ringing…';
  }

  Future<void> _start() async {
    if (isRoom) {
      unawaited(
        _ref
            .read(communityRepositoryProvider)
            .room(roomId!)
            .then((room) {
              roomName = room?.name;
              _notify();
            })
            .catchError((_) {}),
      );
      await _join(video: _video);
      return;
    }
    final call = await _repo.call(callId!).catchError((_) => null);
    if (ended) return;
    if (call == null || call.status == 'ended' || call.status == 'missed' || call.status == 'declined') {
      return end();
    }
    final members = await _repo.members(call.conversationId).catchError((_) => <ConversationMember>[]);
    this.call = call;
    people = {for (final m in members) m.user.id: m.user};
    ringing = !outgoing && call.status == 'ringing';
    _events = _ref.read(inboxRealtimeProvider)?.events.listen((event) {
      if (event is CallChanged && event.row['id'] == call.id) {
        final status = event.row['status'] as String?;
        if (status == 'ended' || status == 'declined' || status == 'missed') end();
      }
    });
    _notify();
    if (!ringing) {
      await _join(video: call.isVideo);
      if (outgoing) {
        _noAnswer = Timer(const Duration(seconds: 45), () {
          if (!(session?.anyoneConnected ?? false)) {
            unawaited(_repo.updateCall(call.id, 'missed').catchError((_) {}));
            end();
          }
        });
      }
    }
  }

  Future<void> _join({required bool video}) async {
    if (ended) return;
    final session = CallSession(repo: _repo, callId: callId, roomId: roomId, video: video);
    session.addListener(_onSession);
    this.session = session;
    _notify();
    await session.join();
    if (ended) return;
    if (session.joined) unawaited(_CallKeepAlive.start(title: title, video: video && session.cameraOn));
  }

  void _onSession() {
    final session = this.session;
    if (session == null || ended) return;
    if (session.anyoneConnected && _clock == null) {
      _noAnswer?.cancel();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed += const Duration(seconds: 1);
        _notify();
      });
      final call = this.call;
      if (call != null && call.status == 'ringing') {
        unawaited(_repo.updateCall(call.id, 'ongoing').catchError((_) {}));
      }
    }
    _notify();
  }

  Future<void> accept() async {
    final call = this.call;
    if (call == null) return;
    _ref.read(incomingCallProvider.notifier).clear();
    ringing = false;
    _notify();
    unawaited(_repo.updateCall(call.id, 'ongoing').catchError((_) {}));
    await _join(video: call.isVideo);
  }

  Future<void> decline() async {
    final call = this.call;
    _ref.read(incomingCallProvider.notifier).clear();
    if (call != null) await _repo.updateCall(call.id, 'declined').catchError((_) {});
    end();
  }

  /// Leaves the call. In a 1:1 call (or when you're the last one) the call is
  /// marked ended, or missed if nobody picked up.
  Future<void> hangUp() async {
    final call = this.call;
    final alone = (session?.remote.length ?? 0) <= 1;
    if (call != null && alone) {
      await _repo.updateCall(call.id, session?.anyoneConnected ?? false ? 'ended' : 'missed').catchError((_) {});
    }
    end();
  }

  /// Tears everything down and tells the app the call is over.
  void end() {
    if (ended) return;
    ended = true;
    _noAnswer?.cancel();
    _clock?.cancel();
    unawaited(_events?.cancel());
    final session = this.session;
    if (session != null) {
      session.removeListener(_onSession);
      unawaited(session.leave());
    }
    unawaited(_CallKeepAlive.stop());
    notifyListeners();
    _onEnded(this);
  }

  void _notify() {
    if (!ended) notifyListeners();
  }
}

/// On Android, a foreground service with an ongoing-call notification keeps
/// the microphone (and camera) working while the app is in the background.
abstract final class _CallKeepAlive {
  static bool _initialized = false;

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start({required String title, required bool video}) async {
    if (!_supported) return;
    try {
      if (!_initialized) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'ongoing_call',
            channelName: 'Ongoing calls',
            channelDescription: 'Shown while you are in a call so it keeps running in the background.',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );
        _initialized = true;
      }
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      final types = [ForegroundServiceTypes.microphone, if (video) ForegroundServiceTypes.camera];
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: 'Call in progress');
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 4101,
          serviceTypes: types,
          notificationTitle: title,
          notificationText: 'Call in progress · tap to return',
        );
      }
    } catch (e) {
      debugPrint('Could not keep the call alive in the background: $e');
    }
  }

  static Future<void> stop() async {
    if (!_supported || !_initialized) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
