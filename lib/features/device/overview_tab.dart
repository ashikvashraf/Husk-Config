import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controls_card.dart';
import 'overview_providers.dart';
import 'sensors_card.dart';
import 'status_cards.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = <Widget>[
      DeviceCard(serverId: serverId),
      ServicesCard(serverId: serverId),
      ControlsCard(serverId: serverId),
      BatteryCard(serverId: serverId),
      ConnectivityCard(serverId: serverId),
      DisplayCard(serverId: serverId),
      LocationCard(serverId: serverId),
      SensorsCard(serverId: serverId),
      MicCard(serverId: serverId),
    ];
    return RefreshIndicator(
      onRefresh: () async => refreshOverview(ref, serverId),
      child: LayoutBuilder(builder: (context, constraints) {
        const gap = 12.0, padding = 16.0;
        final columns = (constraints.maxWidth / 420).floor().clamp(1, 3);
        final width = (constraints.maxWidth - padding * 2 - gap * (columns - 1)) / columns;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(padding),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            TextButton.icon(
              onPressed: () => refreshOverview(ref, serverId),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final card in cards) SizedBox(width: width, child: card)],
            ),
          ]),
        );
      }),
    );
  }
}
