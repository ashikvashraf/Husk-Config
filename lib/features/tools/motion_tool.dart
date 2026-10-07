import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../core/api/models/tools_models.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import 'tools_providers.dart';

class MotionTool extends ConsumerStatefulWidget {
  const MotionTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<MotionTool> createState() => _MotionToolState();
}

class _MotionToolState extends ConsumerState<MotionTool> {
  final _server = TextEditingController();
  final _topic = TextEditingController();
  bool _enabled = false;
  double _sensitivity = 5;
  bool _loaded = false;
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _server.dispose();
    _topic.dispose();
    super.dispose();
  }

  void _load(MotionConfig config) {
    _loaded = true;
    _enabled = config.enabled;
    _server.text = config.ntfyServer;
    _topic.text = config.ntfyTopic;
    _sensitivity = config.sensitivity.clamp(1, 10).toDouble();
  }

  Future<void> _save() async {
    final server = _server.text.trim();
    if (!server.startsWith('https://')) {
      setState(() => _serverError = 'Only https:// servers are accepted.');
      return;
    }
    setState(() {
      _serverError = null;
      _saving = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiProvider(widget.serverId)).setMotion(
            enabled: _enabled,
            topic: _topic.text.trim(),
            server: server,
            sensitivity: _sensitivity.round(),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Motion alarm saved')));
      _loaded = false;
      ref.invalidate(motionProvider(widget.serverId));
    } on HuskException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.serverId;
    ref.watch(apiProvider(id));
    final config = ref.watch(motionProvider(id));
    final events = ref.watch(eventsProvider(id));
    final loaded = config.value;
    if (loaded != null && !_loaded) _load(loaded);

    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Motion alarm',
        icon: Icons.motion_photos_on,
        child: AsyncSection(
          value: config,
          onRetry: () => ref.invalidate(motionProvider(id)),
          builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Detects motion in the camera or screen feed and pushes a snapshot through ntfy.'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Motion alarm'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            TextField(
              controller: _server,
              decoration: InputDecoration(labelText: 'ntfy server', helperText: 'Only https:// is accepted.', errorText: _serverError),
            ),
            TextField(
              controller: _topic,
              decoration: const InputDecoration(labelText: 'ntfy topic', helperText: 'Leave empty to only log events (no push).'),
            ),
            const SizedBox(height: 12),
            Text('Sensitivity: ${_sensitivity.round()} (10 = most sensitive)'),
            Slider(value: _sensitivity, min: 1, max: 10, divisions: 9, onChanged: (v) => setState(() => _sensitivity = v)),
            if (c.lastNtfy.isNotEmpty) InfoRow('Last push', c.lastNtfy),
            const SizedBox(height: 8),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Recent events',
        icon: Icons.history,
        trailing: IconButton(tooltip: 'Refresh events', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(eventsProvider(id))),
        child: AsyncSection(
          value: events,
          onRetry: () => ref.invalidate(eventsProvider(id)),
          builder: (list) => list.isEmpty
              ? const Text('No motion events yet.')
              : Column(children: [
                  for (final e in list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(e.source == 'camera' ? Icons.videocam : Icons.smartphone),
                      title: Text('${e.change.toStringAsFixed(1)} % change'),
                      subtitle: Text('${e.source} · ${e.time.toLocal().toString().substring(0, 19)}'),
                    ),
                ]),
        ),
      ),
    ]);
  }
}
