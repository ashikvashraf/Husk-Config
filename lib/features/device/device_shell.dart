import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/status_dot.dart';
import '../camera/camera_tab.dart';
import '../dashboard/server_status.dart';
import '../screen/screen_tab.dart';
import '../servers/servers_controller.dart';
import '../tools/tools_tab.dart';
import 'overview_tab.dart';

enum DeviceTab { overview, camera, screen, tools }

class DeviceShell extends ConsumerStatefulWidget {
  const DeviceShell({super.key, required this.serverId, required this.tab});

  static DeviceTab parseTab(String? name) => DeviceTab.values.asNameMap()[name] ?? DeviceTab.overview;

  final String serverId;
  final DeviceTab tab;

  @override
  ConsumerState<DeviceShell> createState() => _DeviceShellState();
}

class _DeviceShellState extends ConsumerState<DeviceShell> {
  static const _destinations = [
    (DeviceTab.overview, 'Overview', Icons.dashboard_outlined),
    (DeviceTab.camera, 'Camera', Icons.videocam_outlined),
    (DeviceTab.screen, 'Screen', Icons.smartphone),
    (DeviceTab.tools, 'Tools', Icons.build_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _touch();
  }

  @override
  void didUpdateWidget(DeviceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) _touch();
  }

  void _touch() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(serversProvider.notifier).touch(widget.serverId);
      });

  void _go(int index) => context.go('/device/${widget.serverId}/${DeviceTab.values[index].name}');

  Widget _body() => switch (widget.tab) {
        DeviceTab.overview => OverviewTab(key: ValueKey(widget.serverId), serverId: widget.serverId),
        DeviceTab.camera => CameraTab(key: ValueKey(widget.serverId), serverId: widget.serverId),
        DeviceTab.screen => ScreenTab(key: ValueKey(widget.serverId), serverId: widget.serverId),
        DeviceTab.tools => ToolsTab(serverId: widget.serverId),
      };

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverByIdProvider(widget.serverId));
    if (server == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('This server no longer exists.'),
            TextButton(onPressed: () => context.go('/'), child: const Text('Back to dashboard')),
          ]),
        ),
      );
    }
    final servers = ref.watch(serversProvider);
    final status = ref.watch(serverStatusProvider(server.id));
    final dot = status.value?.dot ?? (status.hasError ? DotState.offline : DotState.unknown);
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'All servers', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
        title: Row(children: [
          StatusDot(dot),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButton<String>(
              value: server.id,
              underline: const SizedBox.shrink(),
              isExpanded: true,
              items: [
                for (final s in servers)
                  DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) {
                if (id != null) context.go('/device/$id/${widget.tab.name}');
              },
            ),
          ),
        ]),
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: widget.tab.index,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: _go,
                destinations: [
                  for (final (_, label, icon) in _destinations) NavigationRailDestination(icon: Icon(icon), label: Text(label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _body()),
            ])
          : _body(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: widget.tab.index,
              onDestinationSelected: _go,
              destinations: [
                for (final (_, label, icon) in _destinations) NavigationDestination(icon: Icon(icon), label: label),
              ],
            ),
    );
  }
}
