import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/providers.dart';
import '../../core/stream/mjpeg_stream.dart';

/// Plays a Husk MJPEG stream (/stream or /screen). Reconnects with backoff
/// (1, 2, 4, 8, 10 s), drops frames that arrive while one is still decoding,
/// and disconnects while the app is in the background or the widget is gone.
class MjpegView extends ConsumerStatefulWidget {
  const MjpegView({
    super.key,
    required this.api,
    required this.path,
    this.fit = BoxFit.contain,
    this.showFps = true,
    this.onFrameSize,
  });

  final HuskApi api;
  final String path;
  final BoxFit fit;
  final bool showFps;

  /// Called with a frame's pixel size whenever it differs from the previous frame's.
  final ValueChanged<Size>? onFrameSize;

  @override
  ConsumerState<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends ConsumerState<MjpegView> {
  ui.Image? _image;
  StreamSubscription<Uint8List>? _subscription;
  CancelToken? _cancelToken;
  Timer? _retryTimer;
  Timer? _fpsTimer;
  int _attempt = 0;
  int _generation = 0;
  String? _status = 'Connecting…';
  bool _decoding = false;
  Uint8List? _pending;
  int _framesThisSecond = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _connect();
    if (widget.showFps) {
      _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final fps = _framesThisSecond;
        _framesThisSecond = 0;
        if (mounted && fps != _fps) setState(() => _fps = fps);
      });
    }
  }

  @override
  void didUpdateWidget(MjpegView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.path != widget.path) {
      _disconnect();
      _attempt = 0;
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnect();
    _fpsTimer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    _cancelToken = CancelToken();
    try {
      final response = await widget.api.openMultipart(widget.path, cancelToken: _cancelToken);
      if (!mounted || generation != _generation) return;
      final boundary = MjpegParser.boundaryFrom(response.contentType);
      if (boundary == null) throw const DeviceErrorException('The phone did not send an MJPEG stream');
      _subscription = response.stream.transform(MjpegParser(boundary)).listen(
            (frame) => _onFrame(frame, generation),
            onError: (Object _) => _scheduleReconnect(generation, 'Connection lost'),
            onDone: () => _scheduleReconnect(generation, 'Stream ended'),
            cancelOnError: true,
          );
    } on HuskException catch (e) {
      _scheduleReconnect(generation, e.message);
    }
  }

  void _disconnect() {
    _generation++;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  void _scheduleReconnect(int generation, String reason) {
    if (!mounted || generation != _generation) return;
    _subscription?.cancel();
    _subscription = null;
    final seconds = math.min(10, 1 << math.min(_attempt, 4));
    _attempt++;
    setState(() => _status = '$reason. Reconnecting in ${seconds}s…');
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (mounted && generation == _generation) _connect();
    });
  }

  void _onFrame(Uint8List bytes, int generation) {
    if (generation != _generation) return;
    _attempt = 0;
    _framesThisSecond++;
    if (_decoding) {
      _pending = bytes; // Keep only the newest frame while decoding.
      return;
    }
    _decode(bytes);
  }

  Future<void> _decode(Uint8List bytes) async {
    _decoding = true;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final old = _image;
      final image = frame.image;
      setState(() {
        _image = image;
        _status = null;
      });
      if (old == null || old.width != image.width || old.height != image.height) {
        widget.onFrameSize?.call(Size(image.width.toDouble(), image.height.toDouble()));
      }
      old?.dispose();
    } catch (_) {
      // A corrupt frame is skipped; the next one replaces it.
    } finally {
      _decoding = false;
      final next = _pending;
      _pending = null;
      if (next != null && mounted) _decode(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appForegroundProvider, (previous, foreground) {
      if (foreground) {
        _attempt = 0;
        _disconnect();
        _connect();
        setState(() => _status = 'Connecting…');
      } else {
        _disconnect();
        setState(() => _status = 'Paused');
      }
    });
    final status = _status;
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (_image != null) RawImage(image: _image, fit: widget.fit),
        if (status != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Text(status, style: const TextStyle(color: Colors.white)),
            ),
          ),
        if (widget.showFps && _image != null)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.black54,
              child: Text('$_fps fps', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
      ]),
    );
  }
}
