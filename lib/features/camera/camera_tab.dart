import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../shared/save_image.dart';
import '../../shared/widgets/mjpeg_view.dart';
import '../device/overview_providers.dart';
import '../servers/api_provider.dart';
import 'snapshot.dart';

class CameraTab extends ConsumerStatefulWidget {
  const CameraTab({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends ConsumerState<CameraTab> {
  int? _rotation;
  bool _flip = false;
  int? _fps;
  bool _busy = false;
  int _streamEpoch = 0;

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _setCamera(HuskApi api, {bool? front, int? rotation, bool? flip, int? fps}) async {
    try {
      final result = await api.setCamera(front: front, rotation: rotation, flip: flip, fps: fps);
      if (result.isErr) {
        _snack(result.text, error: true);
      } else if (mounted) {
        // The phone restarts the camera for the new settings; reconnect now rather than
        // waiting for it to drop the stream (or for the 15 s idle timeout).
        setState(() => _streamEpoch++);
      }
    } on HttpStatusException catch (e) {
      _snack(e.statusCode == 409 ? 'This camera side does not exist on the device.' : e.message, error: true);
    } on HuskException catch (e) {
      _snack(e.message, error: true);
    }
    if (mounted) ref.invalidate(flagsProvider(widget.serverId));
  }

  Future<void> _snapshot(HuskApi api) async {
    setState(() => _busy = true);
    try {
      final bytes = await fetchWithWarmup(api.snapshot);
      if (mounted) await _showSnapshot(bytes);
    } on HuskException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSnapshot(Uint8List bytes) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
            OverflowBar(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed: () => saveImage(buttonContext, bytes, 'husk-snapshot-${DateTime.now().millisecondsSinceEpoch}.jpg'),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save'),
                ),
              ),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    final front = ref.watch(flagsProvider(widget.serverId)).value?.front;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final textTheme = Theme.of(context).textTheme;

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.icon(
        onPressed: _busy ? null : () => _snapshot(api),
        icon: const Icon(Icons.photo_camera),
        label: const Text('Snapshot'),
      ),
      const SizedBox(height: 16),
      Text('Camera side', style: textTheme.labelLarge),
      const SizedBox(height: 4),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Back')),
          ButtonSegment(value: true, label: Text('Front')),
        ],
        selected: {?front},
        emptySelectionAllowed: true,
        onSelectionChanged: (v) {
          if (v.isNotEmpty) _setCamera(api, front: v.first);
        },
      ),
      const SizedBox(height: 16),
      Text('Rotation', style: textTheme.labelLarge),
      const SizedBox(height: 4),
      SegmentedButton<int>(
        segments: [
          for (final degrees in [0, 90, 180, 270]) ButtonSegment(value: degrees, label: Text('$degrees°')),
        ],
        selected: {?_rotation},
        emptySelectionAllowed: true,
        onSelectionChanged: (v) {
          if (v.isEmpty) return;
          setState(() => _rotation = v.first);
          _setCamera(api, rotation: v.first);
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Mirror horizontally'),
        value: _flip,
        onChanged: (v) {
          setState(() => _flip = v);
          _setCamera(api, flip: v);
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Frame rate cap'),
        trailing: DropdownButton<int>(
          value: _fps,
          hint: const Text('Default'),
          items: [for (final f in [1, 5, 10, 15, 30]) DropdownMenuItem(value: f, child: Text('$f fps'))],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _fps = v);
            _setCamera(api, fps: v);
          },
        ),
      ),
      Text(
        'The phone starts the camera on demand and closes it about 4 s after the last viewer.',
        style: textTheme.bodySmall,
      ),
    ]);

    final view = MjpegView(key: ValueKey(_streamEpoch), api: api, path: '/stream');
    if (wide) {
      return Row(children: [
        Expanded(child: view),
        SizedBox(width: 340, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: controls)),
      ]);
    }
    return Column(children: [
      Expanded(flex: 3, child: view),
      Expanded(flex: 2, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: controls)),
    ]);
  }
}
