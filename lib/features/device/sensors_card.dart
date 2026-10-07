import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_api.dart';
import '../../core/api/husk_exception.dart';
import '../../core/api/models/hardware_models.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';
import 'overview_providers.dart';

class SensorsCard extends ConsumerStatefulWidget {
  const SensorsCard({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<SensorsCard> createState() => _SensorsCardState();
}

class _SensorsCardState extends ConsumerState<SensorsCard> {
  String? _type;
  SensorReading? _reading;
  String? _error;
  bool _live = false;
  Timer? _timer;

  @override
  void didUpdateWidget(SensorsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) _stopLive();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Stops live polling; the timer closure holds the HuskApi it started with.
  void _stopLive() {
    _timer?.cancel();
    _timer = null;
    _live = false;
  }

  Future<void> _read(HuskApi api, String type) async {
    try {
      final reading = await api.sensor(type);
      if (mounted && type == _type) {
        setState(() {
          _reading = reading;
          _error = null;
        });
      }
    } on HuskException catch (e) {
      if (mounted && type == _type) {
        setState(() {
          _reading = null;
          _error = e.message;
        });
      }
    }
  }

  void _select(HuskApi api, String type) {
    setState(() {
      _type = type;
      _reading = null;
      _error = null;
    });
    _read(api, type);
  }

  void _setLive(HuskApi api, bool live) {
    _timer?.cancel();
    setState(() => _live = live);
    final type = _type;
    if (live && type != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _read(api, _type ?? type));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    ref.listen(apiProvider(widget.serverId), (_, _) {
      if (_live) setState(_stopLive);
    });
    final reading = _reading;
    return SectionCard(
      title: 'Sensors',
      icon: Icons.sensors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in sensorTypes)
                ChoiceChip(
                  label: Text(type),
                  selected: _type == type,
                  onSelected: (_) => _select(api, type),
                ),
            ],
          ),
          if (_type != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    reading != null
                        ? '${reading.sensor}: ${reading.values.map((v) => v.toStringAsFixed(2)).join(', ')}'
                        : (_error ?? 'Reading…'),
                  ),
                ),
                const Text('Live'),
                Switch(value: _live, onChanged: (v) => _setLive(api, v)),
              ],
            ),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('All sensors'),
            children: [
              AsyncSection(
                value: ref.watch(sensorsProvider(widget.serverId)),
                onRetry: () => ref.invalidate(sensorsProvider(widget.serverId)),
                builder: (list) => Column(
                  children: [
                    for (final s in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.name),
                        subtitle: Text(
                          '${s.vendor} · type ${s.type ?? '?'} · ${s.power ?? '?'} mA · max ${s.max ?? '?'}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MicCard extends ConsumerStatefulWidget {
  const MicCard({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<MicCard> createState() => _MicCardState();
}

class _MicCardState extends ConsumerState<MicCard> {
  MicLevel? _level;
  String? _error;
  bool _live = false;
  Timer? _timer;

  @override
  void didUpdateWidget(MicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) _stopLive();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Stops live polling; the timer closure holds the HuskApi it started with.
  void _stopLive() {
    _timer?.cancel();
    _timer = null;
    _live = false;
  }

  Future<void> _sample(HuskApi api) async {
    try {
      final level = await api.mic();
      if (mounted) {
        setState(() {
          _level = level;
          _error = null;
        });
      }
    } on HuskException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _setLive(HuskApi api, bool live) {
    _timer?.cancel();
    setState(() => _live = live);
    if (live) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample(api));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    ref.listen(apiProvider(widget.serverId), (_, _) {
      if (_live) setState(_stopLive);
    });
    final level = _level;
    return SectionCard(
      title: 'Microphone level',
      icon: Icons.mic,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Live'),
          Switch(value: _live, onChanged: (v) => _setLive(api, v)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: level?.fraction ?? 0),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _error ??
                      (level == null
                          ? 'No sample yet. Audio is never recorded.'
                          : '${level.amplitude} / ${level.max}'),
                ),
              ),
              OutlinedButton(
                onPressed: () => _sample(api),
                child: const Text('Sample'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
