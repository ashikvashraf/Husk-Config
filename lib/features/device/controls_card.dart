import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/run_command.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import 'overview_providers.dart';

String? _brightnessHint(String reply) =>
    reply.contains('WRITE_SETTINGS') ? 'Allow "Modify system settings" for Husk on the phone.' : null;

class ControlsCard extends ConsumerStatefulWidget {
  const ControlsCard({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ControlsCard> createState() => _ControlsCardState();
}

class _ControlsCardState extends ConsumerState<ControlsCard> {
  final _vibrateMs = TextEditingController(text: '300');
  bool _torchOn = false;
  double? _brightnessDrag;
  final Map<String, double> _volumeDrag = {};

  @override
  void dispose() {
    _vibrateMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.serverId;
    final api = ref.watch(apiProvider(id));
    final label = Theme.of(context).textTheme.labelLarge;

    return SectionCard(
      title: 'Quick controls',
      icon: Icons.tune,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Torch'),
          value: _torchOn,
          onChanged: (on) async {
            final result = await runCommand(context, () => api.torch(on: on));
            if (mounted && result != null && !result.isErr) setState(() => _torchOn = on);
          },
        ),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 120,
            child: TextField(
              controller: _vibrateMs,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Vibrate (ms)', isDense: true),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              final ms = (int.tryParse(_vibrateMs.text.trim()) ?? 300).clamp(1, 10000);
              runCommand(context, () => api.vibrate(ms: ms));
            },
            icon: const Icon(Icons.vibration),
            label: const Text('Vibrate'),
          ),
          OutlinedButton.icon(
            onPressed: () => runCommand(context, api.wake, success: 'Screen woken for about 2 minutes'),
            icon: const Icon(Icons.light_mode),
            label: const Text('Wake screen'),
          ),
        ]),
        const Divider(height: 32),
        Text('Brightness', style: label),
        AsyncSection(
          value: ref.watch(brightnessProvider(id)),
          onRetry: () => ref.invalidate(brightnessProvider(id)),
          builder: (b) {
            final max = math.max(b.max, 1).toDouble();
            final value = (_brightnessDrag ?? b.level.toDouble()).clamp(0.0, max);
            return Row(children: [
              Expanded(
                child: Slider(
                  value: value,
                  max: max,
                  divisions: max.toInt(),
                  label: '${value.round()}',
                  onChanged: (v) => setState(() => _brightnessDrag = v),
                  onChangeEnd: (v) async {
                    await runCommand(context, () => api.setBrightness(v.round()), hint: _brightnessHint);
                    if (!mounted) return;
                    setState(() => _brightnessDrag = null);
                    ref.invalidate(brightnessProvider(id));
                  },
                ),
              ),
              if (b.auto) const Chip(label: Text('Auto'), visualDensity: VisualDensity.compact),
            ]);
          },
        ),
        const SizedBox(height: 8),
        Text('Ringer', style: label),
        const SizedBox(height: 4),
        AsyncSection(
          value: ref.watch(ringerProvider(id)),
          onRetry: () => ref.invalidate(ringerProvider(id)),
          builder: (mode) => SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'normal', label: Text('Normal')),
              ButtonSegment(value: 'vibrate', label: Text('Vibrate')),
              ButtonSegment(value: 'silent', label: Text('Silent')),
            ],
            selected: {if (const {'normal', 'vibrate', 'silent'}.contains(mode)) mode},
            emptySelectionAllowed: true,
            onSelectionChanged: (v) async {
              if (v.isEmpty) return;
              await runCommand(context, () => api.setRinger(v.first));
              if (mounted) ref.invalidate(ringerProvider(id));
            },
          ),
        ),
        Text('Silent and vibrate may need Do Not Disturb access for Husk on the phone.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Text('Volume', style: label),
        AsyncSection(
          value: ref.watch(volumeProvider(id)),
          onRetry: () => ref.invalidate(volumeProvider(id)),
          builder: (streams) => Column(children: [
            for (final MapEntry(key: stream, value: level) in streams.entries)
              Row(children: [
                SizedBox(width: 100, child: Text(stream)),
                Expanded(
                  child: Slider(
                    value: (_volumeDrag[stream] ?? level.level.toDouble()).clamp(0.0, math.max(level.max, 1).toDouble()),
                    max: math.max(level.max, 1).toDouble(),
                    divisions: math.max(level.max, 1),
                    onChanged: (v) => setState(() => _volumeDrag[stream] = v),
                    onChangeEnd: (v) async {
                      await runCommand(context, () => api.setVolume(stream, v.round()));
                      if (!mounted) return;
                      setState(() => _volumeDrag.remove(stream));
                      ref.invalidate(volumeProvider(id));
                    },
                  ),
                ),
                SizedBox(width: 48, child: Text('${(_volumeDrag[stream] ?? level.level).round()}/${level.max}')),
              ]),
          ]),
        ),
      ]),
    );
  }
}
