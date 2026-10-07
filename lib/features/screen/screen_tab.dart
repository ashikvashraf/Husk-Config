import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/models/hardware_models.dart';
import '../../core/api/models/tools_models.dart';
import '../../core/storage/app_settings.dart';
import '../../shared/error_text.dart';
import '../../shared/run_command.dart';
import '../../shared/save_image.dart';
import '../../shared/widgets/mjpeg_view.dart';
import '../device/overview_providers.dart';
import '../servers/api_provider.dart';
import '../settings/settings_controller.dart';
import 'gesture_layer.dart';
import 'h264_view.dart';
import 'input_controls.dart';
import 'input_queue.dart';
import 'screen_mode.dart';
import 'web_control_view.dart';

/// Size of one display, keyed by (server id, display id). Display 0 uses the
/// shared [displayInfoProvider].
final _displaySizeProvider = FutureProvider.autoDispose.family<DisplayInfo, (String, int)>((ref, key) {
  final (id, display) = key;
  if (display == 0) return ref.watch(displayInfoProvider(id).future);
  return ref.watch(apiProvider(id)).display(display: display);
});

bool _landscape(Size size) => size.width > size.height;

/// [device] (from /display) turned to match the live frame's orientation. /display
/// is rotation-aware, but it is only re-read after a frame shows the phone
/// rotated; until that answer arrives the frame's orientation wins.
Size orientedDeviceSize(Size device, Size? frame) =>
    frame != null && frame.width != frame.height && _landscape(frame) != _landscape(device) ? device.flipped : device;

String _modeLabel(ScreenMode mode) => switch (mode) {
      ScreenMode.mjpeg => 'MJPEG',
      ScreenMode.h264 => 'H.264',
      ScreenMode.webview => 'Web control',
    };

class ScreenTab extends ConsumerStatefulWidget {
  const ScreenTab({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ScreenTab> createState() => _ScreenTabState();
}

class _ScreenTabState extends ConsumerState<ScreenTab> {
  late final InputQueue _queue = InputQueue(onError: _showInputError);
  int _display = 0;
  bool _fullscreenOpen = false;
  bool _h264Failed = false;

  /// Pixel size of the latest frame on the selected display (MJPEG or H.264).
  final _frameSize = ValueNotifier<Size?>(null);

  @override
  void dispose() {
    _frameSize.dispose();
    super.dispose();
  }

  /// When the live frame turns between portrait and landscape, the phone was
  /// rotated: re-read /display so taps map onto the rotated size.
  void _onFrameSize(Size size) {
    if (!mounted) return;
    final previous = _frameSize.value;
    _frameSize.value = size;
    if (previous != null && _landscape(previous) == _landscape(size)) return;
    if (size.width == size.height) return;
    final id = widget.serverId;
    final info = ref.read(_displaySizeProvider((id, _display))).value;
    if (info == null || _landscape(Size(info.width.toDouble(), info.height.toDouble())) == _landscape(size)) return;
    if (_display == 0) {
      ref.invalidate(displayInfoProvider(id));
    } else {
      ref.invalidate(_displaySizeProvider((id, _display)));
    }
  }

  void _showInputError(Object error) {
    if (!mounted) return;
    final message = describeError(error);
    final hint = message.contains('cancelled')
        ? ' Screen may be off — press Wake.'
        : message.contains('ime-needs-api30')
            ? ' Typing needs Android 11 or newer on the phone.'
            : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message$hint')));
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _interactive(HuskApi api, Size deviceSize, Widget child) => ValueListenableBuilder<Size?>(
        valueListenable: _frameSize,
        child: child,
        builder: (context, frame, child) => GestureLayer(
          deviceSize: orientedDeviceSize(deviceSize, frame),
          onTap: (p) => _queue.add(() => api.tap(p.x, p.y, display: _display)),
          onLongPress: (p) => _queue.add(() => api.tap(p.x, p.y, display: _display, ms: 600)),
          onSwipe: (a, b, d) => _queue.add(() => api.swipe(a.x, a.y, b.x, b.y, display: _display, ms: d.inMilliseconds)),
          onScroll: (forward) => _queue.add(() => api.scroll(display: _display, forward: forward)),
          onKey: (key) => _queue.add(() => api.key(key)),
          child: child!,
        ),
      );

  /// The live view for [mode] on the selected display. [display] is that
  /// display's pixel size from /display.
  Widget _modeView(ScreenMode mode, HuskApi api, AsyncValue<DisplayInfo> display) {
    if (mode == ScreenMode.webview) return WebControlView(api: api);
    final info = display.value;
    if (info == null) {
      final error = display.error;
      return Center(child: error == null ? const CircularProgressIndicator() : Text(describeError(error)));
    }
    final deviceSize = Size(info.width.toDouble(), info.height.toDouble());
    return switch (mode) {
      ScreenMode.mjpeg => _interactive(
          api,
          deviceSize,
          // A new key and path per display so the stream reconnects on the picked one.
          MjpegView(
            key: ValueKey('screen-$_display'),
            api: api,
            path: _display == 0 ? '/screen' : '/screen?d=$_display',
            onFrameSize: _onFrameSize,
          ),
        ),
      ScreenMode.h264 => _interactive(
          api,
          deviceSize,
          H264View(
            uri: api.uri('/screen.mp4'),
            catchUpSeek: h264CatchUpSeek,
            onVideoSize: _onFrameSize,
            onFailed: (message) {
              if (!mounted || _h264Failed) return;
              setState(() => _h264Failed = true);
              _snack('H.264 not supported on this platform — using MJPEG ($message)');
            },
          ),
        ),
      ScreenMode.webview => WebControlView(api: api),
    };
  }

  Widget _controls(HuskApi api) => Column(mainAxisSize: MainAxisSize.min, children: [
        NavBar(onKey: (k) => _queue.add(() => api.key(k)), onWake: () => _queue.add(api.wake)),
        KeyboardPanel(
          onSendText: (t) => _queue.add(() => api.typeText(t)),
          onEnter: () => _queue.add(() => api.key(NavKey.enter)),
        ),
      ]);

  Future<void> _screenshot(HuskApi api) async {
    try {
      final bytes = await api.screenshot();
      if (mounted) await saveImage(context, bytes, 'husk-screen-${DateTime.now().millisecondsSinceEpoch}.jpg');
    } on HttpStatusException catch (e) {
      _snack(e.statusCode == 503 ? 'Screen sharing is off on the phone.' : e.message);
    } on HuskException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _quality(HuskApi api) async {
    var quality = 70.0, fps = 15.0;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Screen stream quality'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('JPEG quality: ${quality.round()} (lower = less lag)'),
            Slider(value: quality, min: 1, max: 100, divisions: 99, onChanged: (v) => setDialogState(() => quality = v)),
            Text('Frames per second: ${fps.round()}'),
            Slider(value: fps, min: 1, max: 30, divisions: 29, onChanged: (v) => setDialogState(() => fps = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (apply == true && mounted) {
      await runCommand(
        context,
        () => api.setCamera(screenQuality: quality.round(), screenFps: fps.round()),
        success: 'Stream quality updated',
      );
    }
  }

  Future<void> _openFullscreen(ScreenMode mode, HuskApi api) async {
    setState(() => _fullscreenOpen = true); // Avoid two streams while the route is on top.
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            // Watch /display here too, so a re-read after a rotation reaches this route.
            Positioned.fill(
              child: Consumer(
                builder: (context, ref, _) => _modeView(mode, api, ref.watch(_displaySizeProvider((widget.serverId, _display)))),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Exit fullscreen',
                icon: const Icon(Icons.fullscreen_exit),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: mode == ScreenMode.webview ? null : Material(child: _controls(api)),
      ),
    ));
    if (mounted) setState(() => _fullscreenOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.serverId;
    final api = ref.watch(apiProvider(id));
    final flags = ref.watch(flagsProvider(id));
    final display = ref.watch(_displaySizeProvider((id, _display)));
    final displays = ref.watch(displaysProvider(id)).value ?? const [DisplayEntry(id: 0, raw: '0')];
    final available = availableScreenModes(
      // /screen.mp4 is only specified for the main display, so other displays use MJPEG.
      h264Supported: h264Platforms.contains(defaultTargetPlatform) && _display == 0,
      h264Failed: _h264Failed,
    );
    final mode = effectiveScreenMode(
      session: ref.watch(sessionScreenModeProvider),
      defaultMode: ref.watch(settingsProvider.select((s) => s.defaultScreenMode)),
      available: available,
    );
    final displayIds = {for (final d in displays) d.id, _display};

    final Widget body;
    if (_fullscreenOpen) {
      body = const Center(child: Text('Showing fullscreen'));
    } else if (flags.value?.screen == false) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.screen_share_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Screen sharing is off. Enable it in the Husk app on the phone.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => ref.invalidate(flagsProvider(id)), child: const Text('Retry')),
          ]),
        ),
      );
    } else if (flags.value == null) {
      body = Center(child: flags.hasError ? Text(describeError(flags.error!)) : const CircularProgressIndicator());
    } else {
      body = _modeView(mode, api, display);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (available.length > 1)
            SegmentedButton<ScreenMode>(
              segments: [for (final m in available) ButtonSegment(value: m, label: Text(_modeLabel(m)))],
              selected: {mode},
              onSelectionChanged: (v) => ref.read(sessionScreenModeProvider.notifier).set(v.first),
            ),
          DropdownButton<int>(
            value: _display,
            items: [
              for (final d in displayIds) DropdownMenuItem(value: d, child: Text(d == 0 ? 'Phone (display 0)' : 'Display $d')),
            ],
            onChanged: (v) {
              _frameSize.value = null; // The next frame comes from the newly picked display.
              setState(() => _display = v ?? 0);
            },
          ),
          IconButton(tooltip: 'Screenshot', icon: const Icon(Icons.screenshot_monitor), onPressed: () => _screenshot(api)),
          IconButton(tooltip: 'Stream quality', icon: const Icon(Icons.high_quality), onPressed: () => _quality(api)),
          IconButton(
            tooltip: 'Fullscreen',
            icon: const Icon(Icons.fullscreen),
            onPressed: () => _openFullscreen(mode, api),
          ),
        ]),
      ),
      Expanded(child: body),
      if (mode != ScreenMode.webview) _controls(api),
    ]);
  }
}
