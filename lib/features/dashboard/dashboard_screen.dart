import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../servers/servers_controller.dart';
import 'server_card.dart';
import 'server_status.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool? _reported;

  /// Tells the status providers whether this screen is the topmost route.
  /// Reported after the frame because providers must not change during build.
  void _reportVisibility() {
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (visible == _reported) return;
    _reported = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(dashboardVisibleProvider.notifier).set(_reported ?? true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reportVisibility();
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Husk Config'),
        actions: [
          if (servers.isNotEmpty)
            IconButton(tooltip: 'Scan network', icon: const Icon(Icons.wifi_find), onPressed: () => context.push('/servers/scan')),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(serverStatusProvider)),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings), onPressed: () => context.push('/settings')),
        ],
      ),
      floatingActionButton: servers.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/servers/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add server'),
            ),
      body: servers.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(serverStatusProvider),
              child: LayoutBuilder(builder: (context, constraints) {
                const gap = 12.0, padding = 16.0;
                final columns = (constraints.maxWidth / 360).floor().clamp(1, 4);
                final cardWidth = (constraints.maxWidth - padding * 2 - gap * (columns - 1)) / columns;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(padding, padding, padding, 96),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [for (final s in servers) SizedBox(width: cardWidth, child: ServerCard(server: s))],
                  ),
                );
              }),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_android, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No Husk servers yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Add a phone running Husk by its IP address, or scan your network to find it.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              FilledButton.icon(onPressed: () => context.push('/servers/new'), icon: const Icon(Icons.add), label: const Text('Add server')),
              OutlinedButton.icon(onPressed: () => context.push('/servers/scan'), icon: const Icon(Icons.wifi_find), label: const Text('Scan network')),
            ]),
          ],
        ),
      ),
    );
  }
}
