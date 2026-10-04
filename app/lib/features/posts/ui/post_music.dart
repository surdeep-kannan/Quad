import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/media.dart';
import '../../../core/data/refs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/sheets.dart';

/// Which post's music is playing (by post id). One shared player, so starting
/// one post's music stops any other.
final postMusicProvider = NotifierProvider<PostMusicPlayer, String?>(PostMusicPlayer.new);

class PostMusicPlayer extends Notifier<String?> {
  AudioPlayer? _player;

  @override
  String? build() {
    ref.onDispose(() => _player?.dispose());
    return null;
  }

  AudioPlayer get _audio => _player ??= AudioPlayer();

  Future<void> play(String postId, MediaItem music) async {
    state = postId;
    try {
      final total = await _audio.setUrl(music.url);
      if (state != postId) return;
      final start = Duration(milliseconds: music.startMs ?? 0);
      var end = start + Duration(milliseconds: music.durationMs ?? 30000);
      if (total != null && end > total) end = total;
      await _audio.setClip(start: start, end: end);
      await _audio.setLoopMode(LoopMode.one);
      if (state != postId) return;
      // play() only completes when playback stops, so don't wait for it.
      unawaited(_audio.play());
    } catch (_) {
      if (state == postId) state = null;
    }
  }

  /// Stops the music, or only [postId]'s if given.
  Future<void> stop([String? postId]) async {
    if (postId != null && state != postId) return;
    state = null;
    await _player?.stop();
  }

  Future<void> toggle(String postId, MediaItem music) => state == postId ? stop() : play(postId, music);
}

/// "♪ Song name" on a photo post. Tap to play or pause; [autoplay] starts it
/// right away (the post page). Stops when the post leaves the screen.
class PostMusicBadge extends ConsumerStatefulWidget {
  const PostMusicBadge({super.key, required this.postId, required this.music, this.autoplay = false});

  final String postId;
  final MediaItem music;
  final bool autoplay;

  @override
  ConsumerState<PostMusicBadge> createState() => _PostMusicBadgeState();
}

class _PostMusicBadgeState extends ConsumerState<PostMusicBadge> {
  late final PostMusicPlayer _player = ref.read(postMusicProvider.notifier);

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _player.play(widget.postId, widget.music);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another screen covered this one.
    if (!TickerMode.valuesOf(context).enabled) unawaited(_player.stop(widget.postId));
  }

  @override
  void dispose() {
    unawaited(_player.stop(widget.postId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = ref.watch(postMusicProvider) == widget.postId;
    return Semantics(
      button: true,
      label: playing ? 'Pause music' : 'Play music: ${widget.music.title ?? 'song'}',
      child: GestureDetector(
        onTap: () => _player.toggle(widget.postId, widget.music),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              playing ? const _Equalizer() : const Icon(AppIcons.musicFill, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.music.title ?? 'Original audio',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three bouncing bars while music plays.
class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 14,
      child: AnimatedBuilder(
        animation: _bars,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 3,
                height: 4 + 10 * (0.5 + 0.5 * math.sin((_bars.value + i * 0.33) * 2 * math.pi)).abs(),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1.5)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Picks a song from the device, uploads it, then lets the student choose the
/// clip. With [current], just re-opens the clip editor.
Future<MediaItem?> pickPostMusic(BuildContext context, WidgetRef ref, {MediaItem? current}) async {
  var music = current;
  if (music == null) {
    final file = await MediaPicker.audio();
    if (file == null || !context.mounted) return null;
    if (!file.mimeType.startsWith('audio/')) {
      showToast(context, 'Pick a song file (MP3, M4A, AAC, WAV or OGG).', error: true);
      return null;
    }
    if (file.size > 15 * 1024 * 1024) {
      showToast(context, 'Songs can be up to 15 MB.', error: true);
      return null;
    }
    unawaited(ref.read(postMusicProvider.notifier).stop());
    try {
      final url = await _withProgress(
        context,
        'Adding song…',
        ref.read(storageRepositoryProvider).uploadMedia(file, folder: 'music'),
      );
      music = MediaItem(url: url, type: 'audio', title: _titleFrom(file.name), startMs: 0, durationMs: 30000);
    } catch (error) {
      if (context.mounted) showToast(context, friendlyError(error), error: true);
      return null;
    }
    if (!context.mounted) return null;
  }
  return showAppSheet<MediaItem>(context, builder: (_) => _MusicClipSheet(music: music!));
}

String _titleFrom(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final cleaned = base.replaceAll(RegExp(r'[_]+'), ' ').trim();
  return cleaned.isEmpty ? 'Original audio' : cleaned.substring(0, math.min(cleaned.length, 60));
}

Future<T> _withProgress<T>(BuildContext context, String label, Future<T> work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 16),
              Text(label),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await work;
  } finally {
    navigator.pop();
  }
}

/// Choose which part of the song plays (15 or 30 seconds) and its title.
class _MusicClipSheet extends StatefulWidget {
  const _MusicClipSheet({required this.music});

  final MediaItem music;

  @override
  State<_MusicClipSheet> createState() => _MusicClipSheetState();
}

class _MusicClipSheetState extends State<_MusicClipSheet> {
  final _preview = AudioPlayer();
  late final _title = TextEditingController(text: widget.music.title);
  late int _startMs = widget.music.startMs ?? 0;
  late int _clipMs = (widget.music.durationMs ?? 30000) <= 15000 ? 15000 : 30000;
  int? _totalMs;
  bool _playing = false;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _playingSub = _preview.playingStream.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    _preview
        .setUrl(widget.music.url)
        .then((total) {
          if (!mounted) return;
          setState(() {
            _totalMs = total?.inMilliseconds;
            _startMs = math.min(_startMs, _maxStart);
          });
        })
        .catchError((_) {
          if (mounted) setState(() => _totalMs = 0);
        });
  }

  @override
  void dispose() {
    unawaited(_playingSub?.cancel());
    unawaited(_preview.dispose());
    _title.dispose();
    super.dispose();
  }

  int get _maxStart => math.max(0, (_totalMs ?? 0) - _clipMs);

  Future<void> _togglePreview() => _playing ? _preview.pause() : _playClip();

  /// Plays the chosen clip from its start.
  Future<void> _playClip() async {
    final start = Duration(milliseconds: _startMs);
    var end = start + Duration(milliseconds: _clipMs);
    final total = _totalMs;
    if (total != null && total > 0 && end.inMilliseconds > total) end = Duration(milliseconds: total);
    await _preview.setClip(start: start, end: end);
    await _preview.seek(Duration.zero);
    unawaited(_preview.play());
  }

  String _clock(int ms) {
    final seconds = ms ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = _totalMs;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl + context.safePadding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Music for your post', style: context.text.headlineSmall),
          const SizedBox(height: 4),
          Text('Only share music you have the rights to use.', style: context.text.bodySmall),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _title,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Song name', prefixIcon: Icon(AppIcons.music, size: 18)),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Text('Clip length', style: context.text.labelLarge),
              const Spacer(),
              for (final ms in [15000, 30000])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text('${ms ~/ 1000} s'),
                    selected: _clipMs == ms,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _clipMs = ms;
                      _startMs = math.min(_startMs, _maxStart);
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.inkInverse),
                tooltip: _playing ? 'Pause' : 'Play the clip',
                onPressed: total == null ? null : _togglePreview,
                icon: Icon(_playing ? AppIcons.pause : AppIcons.play),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: total == null
                    ? Text('Loading the song…', style: context.text.bodySmall)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plays ${_clock(_startMs)} – ${_clock(math.min(_startMs + _clipMs, math.max(total, _clipMs)))}',
                            style: context.text.titleSmall,
                          ),
                          Slider(
                            value: _startMs.toDouble().clamp(0, _maxStart.toDouble()),
                            max: math.max(_maxStart, 1).toDouble(),
                            onChanged: _maxStart == 0 ? null : (value) => setState(() => _startMs = value.round()),
                            onChangeEnd: (_) {
                              // Hear the new start straight away.
                              if (_playing) unawaited(_playClip());
                            },
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (total != null && total > 0)
            Text('Song length ${_clock(total)}', style: context.text.bodySmall!.copyWith(color: c.inkSubtle)),
          const SizedBox(height: Space.xl),
          AppButton(
            label: 'Use this clip',
            expand: true,
            onPressed: () => Navigator.of(context).pop(
              MediaItem(
                url: widget.music.url,
                type: 'audio',
                title: _title.text.trim().isEmpty ? 'Original audio' : _title.text.trim(),
                startMs: _startMs,
                durationMs: _clipMs,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
