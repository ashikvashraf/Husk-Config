import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/result_box.dart';
import '../servers/api_provider.dart';

class InspectTool extends ConsumerStatefulWidget {
  const InspectTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<InspectTool> createState() => _InspectToolState();
}

class _InspectToolState extends ConsumerState<InspectTool> {
  final _match = TextEditingController();
  final _display = TextEditingController(text: '0');
  final _filter = TextEditingController();
  String? _result;
  bool _resultIsError = false;
  ({int x, int y})? _found;
  String? _dump;
  bool _busy = false;

  int get _d => int.tryParse(_display.text.trim()) ?? 0;
  String get _m => _match.text.trim();

  @override
  void dispose() {
    _match.dispose();
    _display.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action, {bool needsPattern = true}) async {
    if (needsPattern && _m.isEmpty) {
      setState(() {
        _result = 'Enter a regular expression to match text or content descriptions.';
        _resultIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _found = null;
    });
    try {
      final text = await action();
      if (mounted) {
        setState(() {
          _result = text;
          _resultIsError = text.startsWith('ERR');
        });
      }
    } on HuskException catch (e) {
      if (mounted) {
        setState(() {
          _result = e.message;
          _resultIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    final dump = _dump;
    final filter = _filter.text.trim().toLowerCase();
    final dumpLines = dump == null
        ? const <String>[]
        : [for (final line in dump.split('\n')) if (filter.isEmpty || line.toLowerCase().contains(filter)) line];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _match,
            decoration: const InputDecoration(labelText: 'Pattern (regex)', hintText: 'Wi-?Fi|WLAN'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: TextField(controller: _display, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Display')),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final point = await api.find(_m, display: _d);
                    _found = point;
                    return point == null ? 'No match' : 'Found at ${point.x}, ${point.y}';
                  }),
          child: const Text('Find'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() async => await api.exists(_m, display: _d) ? 'Yes, a matching element exists' : 'No matching element'),
          child: const Text('Exists'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() async => await api.getText(_m, display: _d) ?? 'No match'),
          child: const Text('Get text'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(() async => (await api.click(_m, display: _d)).text),
          child: const Text('Click'),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(needsPattern: false, () async {
                    final tree = await api.dump(display: _d);
                    setState(() => _dump = tree);
                    return 'Dumped ${tree.split('\n').length} lines';
                  }),
          child: const Text('Dump'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(needsPattern: false, () async => (await api.scroll(display: _d)).text),
          child: const Text('Scroll forward'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(needsPattern: false, () async => (await api.scroll(display: _d, forward: false)).text),
          child: const Text('Scroll back'),
        ),
      ]),
      if (_result != null) ...[
        const SizedBox(height: 16),
        ResultBox(_result!, isError: _resultIsError),
      ],
      if (_found case final point?) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => _run(needsPattern: false, () async => (await api.tap(point.x, point.y, display: _d)).text),
            child: const Text('Tap here'),
          ),
        ),
      ],
      if (dump != null) ...[
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(labelText: 'Filter lines', prefixIcon: Icon(Icons.filter_list)),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: 'Copy dump',
            icon: const Icon(Icons.copy),
            onPressed: () => Clipboard.setData(ClipboardData(text: dump)),
          ),
        ]),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 480),
          decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(8),
            children: [for (final line in dumpLines) Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))],
          ),
        ),
      ],
    ]);
  }
}
