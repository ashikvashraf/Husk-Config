import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'latency_drift.dart';

/// Plays Husk's live fMP4 /screen.mp4 with mpv's low-latency settings.
/// Calls [onFailed] on any player error, or when playback keeps drifting more
/// than ~2 s behind the live edge, so the tab can fall back to MJPEG.
class H264View extends StatefulWidget {
  const H264View({super.key, required this.uri, required this.onFailed, this.catchUpSeek = true, this.onVideoSize});

  final Uri uri;
  final ValueChanged<String> onFailed;
  final bool catchUpSeek;

  /// Called with the video's display size whenever mpv reports new video parameters.
  final ValueChanged<Size>? onVideoSize;

  @override
  State<H264View> createState() => _H264ViewState();
}

class _H264ViewState extends State<H264View> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<String>? _errors;
  StreamSubscription<Duration>? _positions;
  StreamSubscription<VideoParams>? _videoParams;
  final _clock = Stopwatch();
  final _drift = LatencyDriftMonitor();
  Timer? _watchdog;
  bool _disposed = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('profile', 'low-latency');
        if (_disposed) return;
        await native.setProperty('cache', 'no');
        if (_disposed) return;
        await native.setProperty('untimed', 'yes');
        if (_disposed) return;
      }
      // mpv errors may echo the URL; strip it so the token never reaches the UI.
      _errors = _player.stream.error.listen((e) => _fail(e.replaceAll(widget.uri.toString(), '/screen.mp4')));
      _positions = _player.stream.position.listen((position) {
        if (!_clock.isRunning) _clock.start();
        if (_drift.sample(_clock.elapsed, position)) _fail('latency drifted past 2 s');
      });
      _videoParams = _player.stream.videoParams.listen((p) {
        final w = p.dw ?? p.w, h = p.dh ?? p.h;
        if (!_disposed && w != null && h != null && w > 0 && h > 0) widget.onVideoSize?.call(Size(w.toDouble(), h.toDouble()));
      });
      await _player.open(Media(widget.uri.toString()));
      if (_disposed) return;
      if (widget.catchUpSeek) {
        _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
          final state = _player.state;
          if (state.buffer - state.position > const Duration(seconds: 2)) _player.seek(state.buffer);
        });
      }
    } catch (e) {
      // The error text may echo the URL (and its token), so report only a generic reason.
      _fail('could not start the player');
    }
  }

  void _fail(String message) {
    if (_failed || _disposed || !mounted) return;
    _failed = true;
    widget.onFailed(message);
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _errors?.cancel();
    _positions?.cancel();
    _videoParams?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain, fill: Colors.black);
}
