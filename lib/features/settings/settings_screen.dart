import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/storage/app_settings.dart';
import '../servers/server_actions.dart';
import '../servers/servers_controller.dart';
import 'settings_controller.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final servers = ref.watch(serversProvider);
    final controller = ref.read(settingsProvider.notifier);
    final version = ref.watch(appVersionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Header('Appearance'),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) => controller.update((s) => s.copyWith(themeMode: v.first)),
              ),
              const _Header('Live status'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Polling interval'),
                subtitle: const Text('How often the dashboard and status cards refresh while visible.'),
                trailing: DropdownButton<int>(
                  value: settings.pollIntervalSeconds,
                  items: [
                    for (final seconds in AppSettings.pollIntervalOptions)
                      DropdownMenuItem(value: seconds, child: Text(seconds == 0 ? 'Off' : '$seconds s')),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.update((s) => s.copyWith(pollIntervalSeconds: v));
                  },
                ),
              ),
              const _Header('Screen view'),
              const Text('Default mode when opening the Screen tab.'),
              const SizedBox(height: 8),
              SegmentedButton<ScreenMode>(
                segments: const [
                  ButtonSegment(value: ScreenMode.mjpeg, label: Text('MJPEG')),
                  ButtonSegment(value: ScreenMode.h264, label: Text('H.264')),
                  ButtonSegment(value: ScreenMode.webview, label: Text('Web control')),
                ],
                selected: {settings.defaultScreenMode},
                onSelectionChanged: (v) => controller.update((s) => s.copyWith(defaultScreenMode: v.first)),
              ),
              const _Header('Access token'),
              _ClientNameField(
                initialValue: settings.tokenClientName,
                onValid: (name) => controller.update((s) => s.copyWith(tokenClientName: name)),
              ),
              const _Header('Servers'),
              for (final server in servers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(server.name),
                  subtitle: Text(server.address),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => context.push('/servers/${server.id}/edit')),
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete), onPressed: () => confirmDeleteServer(context, ref, server)),
                  ]),
                ),
              Wrap(spacing: 12, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => context.push('/servers/new'), icon: const Icon(Icons.add), label: const Text('Add server')),
                OutlinedButton.icon(onPressed: () => context.push('/servers/scan'), icon: const Icon(Icons.wifi_find), label: const Text('Scan network')),
              ]),
              const _Header('About'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Husk Config'),
                subtitle: Text(version.value ?? '…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _ClientNameField extends StatelessWidget {
  const _ClientNameField({required this.initialValue, required this.onValid});

  final String initialValue;
  final ValueChanged<String> onValid;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initialValue,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: const InputDecoration(
          labelText: 'Token client name',
          helperText: 'Shown in the approval notification on the phone.',
        ),
        validator: (v) => AppSettings.isValidClientName(v ?? '') ? null : 'Use letters, digits, space, dot, underscore or dash (max 32).',
        onChanged: (v) {
          if (AppSettings.isValidClientName(v)) onValid(v);
        },
      );
}
