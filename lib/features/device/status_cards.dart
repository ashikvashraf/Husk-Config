import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/section_card.dart';
import 'overview_providers.dart';

String _yesNo(bool v) => v ? 'Yes' : 'No';
String _orDash(String? v) => v == null || v.isEmpty ? '—' : v;

class DeviceCard extends ConsumerWidget {
  const DeviceCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Device',
        icon: Icons.phone_android,
        child: AsyncSection(
          value: ref.watch(deviceInfoProvider(serverId)),
          onRetry: () => ref.invalidate(deviceInfoProvider(serverId)),
          builder: (i) => Column(children: [
            InfoRow('Model', i.displayName),
            InfoRow('Android', '${i.androidRelease} (SDK ${i.sdkInt ?? '?'})'),
            InfoRow('Husk', '${i.appVersionName} (${i.appVersionCode})'),
            InfoRow('Screen', '${i.screenWidth ?? '?'} × ${i.screenHeight ?? '?'}'),
            InfoRow('Local IP', _orDash(i.localIp)),
            InfoRow('Tailscale IP', _orDash(i.tailscaleIp)),
            InfoRow('Camera', _yesNo(i.hasCamera)),
            InfoRow('DeX capable', _yesNo(i.dexCapable)),
          ]),
        ),
      );
}

class ServicesCard extends ConsumerWidget {
  const ServicesCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Services',
        icon: Icons.miscellaneous_services,
        child: AsyncSection(
          value: ref.watch(flagsProvider(serverId)),
          onRetry: () => ref.invalidate(flagsProvider(serverId)),
          builder: (f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              _FlagChip('Accessibility', f.a11y),
              _FlagChip('Camera active', f.camera),
              _FlagChip('Screen sharing', f.screen),
              _FlagChip('Motion alarm', f.motion),
              _FlagChip('ntfy topic set', f.ntfy),
              _FlagChip('Battery optimisation off', f.batteryOptIgnored),
              _FlagChip('DeX reconnect', f.dexReconnect),
            ]),
            const SizedBox(height: 8),
            InfoRow('Selected camera', f.front ? 'Front' : 'Back'),
            if (f.lastNtfy.isNotEmpty) InfoRow('Last push', f.lastNtfy),
            const SizedBox(height: 4),
            Text(
              'Camera inactive is normal: it starts on demand and closes a few seconds after the last viewer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      );
}

class _FlagChip extends StatelessWidget {
  const _FlagChip(this.label, this.on);

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(on ? Icons.check_circle : Icons.cancel_outlined, size: 18, color: on ? Colors.green : null),
        label: Text(label),
      );
}

class BatteryCard extends ConsumerWidget {
  const BatteryCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Battery',
        icon: Icons.battery_full,
        child: AsyncSection(
          value: ref.watch(batteryProvider(serverId)),
          onRetry: () => ref.invalidate(batteryProvider(serverId)),
          builder: (b) => Column(children: [
            InfoRow('Level', b.level == null ? '—' : '${b.level}%'),
            InfoRow('Charging', _yesNo(b.charging)),
            InfoRow('Status', _orDash(b.status)),
            InfoRow('Health', _orDash(b.health)),
            InfoRow('Plugged', _orDash(b.plugged)),
            InfoRow('Temperature', b.temperatureC == null ? '—' : '${b.temperatureC!.toStringAsFixed(1)} °C'),
            InfoRow('Voltage', b.voltageMv == null ? '—' : '${b.voltageMv} mV'),
            InfoRow('Technology', _orDash(b.technology)),
          ]),
        ),
      );
}

class ConnectivityCard extends ConsumerWidget {
  const ConnectivityCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Connectivity',
        icon: Icons.wifi,
        child: AsyncSection(
          value: ref.watch(connectivityProvider(serverId)),
          onRetry: () => ref.invalidate(connectivityProvider(serverId)),
          builder: (c) => Column(children: [
            InfoRow('Type', c.type),
            InfoRow('Connected', _yesNo(c.connected)),
            InfoRow('Metered', _yesNo(c.metered)),
            InfoRow('Validated', _yesNo(c.validated)),
          ]),
        ),
      );
}

class DisplayCard extends ConsumerWidget {
  const DisplayCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Display',
        icon: Icons.aspect_ratio,
        child: AsyncSection(
          value: ref.watch(displayInfoProvider(serverId)),
          onRetry: () => ref.invalidate(displayInfoProvider(serverId)),
          builder: (d) => Column(children: [
            InfoRow('Resolution', '${d.width} × ${d.height}'),
            InfoRow('Density', '${d.densityDpi ?? '?'} dpi (${d.density?.toStringAsFixed(2) ?? '?'}×)'),
            InfoRow('Refresh rate', d.refreshHz == null ? '—' : '${d.refreshHz!.toStringAsFixed(0)} Hz'),
            InfoRow('Rotation', '${d.rotation}'),
          ]),
        ),
      );
}

class LocationCard extends ConsumerWidget {
  const LocationCard({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SectionCard(
        title: 'Location',
        icon: Icons.place,
        child: AsyncSection(
          value: ref.watch(locationProvider(serverId)),
          onRetry: () => ref.invalidate(locationProvider(serverId)),
          builder: (l) {
            final lat = l.lat, lon = l.lon;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow('Position', lat == null || lon == null ? '—' : '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'),
              InfoRow('Accuracy', l.accuracyM == null ? '—' : '±${l.accuracyM!.toStringAsFixed(0)} m'),
              InfoRow('Altitude', l.altitude == null ? '—' : '${l.altitude!.toStringAsFixed(0)} m'),
              InfoRow('Time', l.time == null ? '—' : l.time!.toLocal().toString().substring(0, 19)),
              InfoRow('Provider', _orDash(l.provider)),
              if (lat != null && lon != null)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lon')),
                  icon: const Icon(Icons.map),
                  label: const Text('Open in maps'),
                ),
            ]);
          },
        ),
      );
}
