import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/husk_exception.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/result_box.dart';
import '../../shared/widgets/section_card.dart';
import '../servers/api_provider.dart';

class ManagementTool extends ConsumerStatefulWidget {
  const ManagementTool({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ManagementTool> createState() => _ManagementToolState();
}

class _ManagementToolState extends ConsumerState<ManagementTool> {
  Widget? _wdResult;
  Widget? _pairResult;
  Widget? _devResult;
  bool _probeOnly = true;
  bool _wdBusy = false;
  bool _pairBusy = false;
  bool _devBusy = false;

  Future<Widget> _guard(Future<Widget> Function() action) async {
    try {
      return await action();
    } on HuskException catch (e) {
      return ResultBox(e.message, isError: true);
    }
  }

  Future<void> _run({
    required bool Function() isBusy,
    required void Function(bool) setBusy,
    required Future<bool> Function() confirmed,
    required Future<Widget> Function() action,
    required void Function(Widget) setResult,
  }) async {
    if (isBusy()) return;
    if (!await confirmed() || !mounted || isBusy()) return;
    setState(() => setBusy(true));
    final result = await _guard(action);
    if (mounted) {
      setState(() {
        setBusy(false);
        setResult(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider(widget.serverId));
    return ListView(padding: const EdgeInsets.all(16), children: [
      SectionCard(
        title: 'Wireless Debugging',
        icon: Icons.adb,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Re-enables Wireless Debugging through the phone's Settings and returns its address (Android 11+)."),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _wdBusy
                ? null
                : () => _run(
                      isBusy: () => _wdBusy,
                      setBusy: (v) => _wdBusy = v,
                      setResult: (w) => _wdResult = w,
                      confirmed: () => confirm(
                        context,
                        title: 'Enable Wireless Debugging?',
                        message: "Husk will open Settings on the phone and toggle Wireless Debugging with accessibility. The phone's screen will change while this runs.",
                        confirmLabel: 'Enable',
                      ),
                      action: () async {
                        final wd = await api.wd();
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          InfoRow('Address', wd.ipport),
                          _CopyCommand('adb connect ${wd.ipport}'),
                        ]);
                      },
                    ),
            child: const Text('Enable Wireless Debugging'),
          ),
          if (_wdBusy) const _BusyBar(),
          ?_wdResult,
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Pair',
        icon: Icons.link,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Starts Wireless Debugging pairing and returns the pairing address and code (Android 11+).'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _pairBusy
                ? null
                : () => _run(
                      isBusy: () => _pairBusy,
                      setBusy: (v) => _pairBusy = v,
                      setResult: (w) => _pairResult = w,
                      confirmed: () => confirm(
                        context,
                        title: 'Start pairing?',
                        message: 'Husk will open the Wireless Debugging pairing dialog on the phone.',
                        confirmLabel: 'Start',
                      ),
                      action: () async {
                        final pair = await api.pair();
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          InfoRow('Address', pair.addr),
                          InfoRow('Code', pair.code),
                          _CopyCommand('adb pair ${pair.addr} ${pair.code}'),
                        ]);
                      },
                    ),
            child: const Text('Start pairing'),
          ),
          if (_pairBusy) const _BusyBar(),
          ?_pairResult,
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Developer options',
        icon: Icons.developer_mode,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Probe only (navigate, don't tap Build number)"),
            value: _probeOnly,
            onChanged: (v) => setState(() => _probeOnly = v ?? true),
          ),
          OutlinedButton(
            onPressed: _devBusy
                ? null
                : () {
                    final probe = _probeOnly;
                    _run(
                      isBusy: () => _devBusy,
                      setBusy: (v) => _devBusy = v,
                      setResult: (w) => _devResult = w,
                      confirmed: () => confirm(
                        context,
                        title: probe ? 'Check Developer options?' : 'Unlock Developer options?',
                        message: probe
                            ? 'Husk will open Settings › About phone on the phone.'
                            : 'Husk will open Settings › About phone and tap Build number until Developer options are enabled.',
                        confirmLabel: probe ? 'Check' : 'Unlock',
                      ),
                      action: () async {
                        final r = await api.devOptions(probe: probe);
                        return ResultBox(r.text, isError: r.isErr);
                      },
                    );
                  },
            child: const Text('Run'),
          ),
          if (_devBusy) const _BusyBar(),
          ?_devResult,
        ]),
      ),
    ]);
  }
}

class _BusyBar extends StatelessWidget {
  const _BusyBar();

  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator());
}

class _CopyCommand extends StatelessWidget {
  const _CopyCommand(this.command);

  final String command;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: SelectableText(command, style: const TextStyle(fontFamily: 'monospace'))),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: command));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
          },
        ),
      ]);
}
