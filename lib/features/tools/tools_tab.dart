import 'package:flutter/material.dart';

import 'inspect_tool.dart';
import 'launch_tool.dart';
import 'management_tool.dart';
import 'motion_tool.dart';
import 'rpc_tool.dart';
import 'token_tool.dart';

enum ToolPage {
  inspect('Inspect', Icons.manage_search),
  launch('Launch', Icons.open_in_new),
  motion('Motion alarm', Icons.motion_photos_on),
  management('Management', Icons.adb),
  rpc('RPC console', Icons.terminal),
  token('Access token', Icons.key);

  const ToolPage(this.label, this.icon);

  final String label;
  final IconData icon;
}

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key, required this.serverId});

  final String serverId;

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  ToolPage _selected = ToolPage.inspect;

  Widget _page(ToolPage page) => switch (page) {
        ToolPage.inspect => InspectTool(serverId: widget.serverId),
        ToolPage.launch => LaunchTool(serverId: widget.serverId),
        ToolPage.motion => MotionTool(serverId: widget.serverId),
        ToolPage.management => ManagementTool(serverId: widget.serverId),
        ToolPage.rpc => RpcTool(serverId: widget.serverId),
        ToolPage.token => TokenTool(serverId: widget.serverId),
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Row(children: [
            SizedBox(
              width: 220,
              child: ListView(children: [
                for (final page in ToolPage.values)
                  ListTile(
                    leading: Icon(page.icon),
                    title: Text(page.label),
                    selected: page == _selected,
                    onTap: () => setState(() => _selected = page),
                  ),
              ]),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _page(_selected)),
          ]);
        }
        return ListView(children: [
          for (final page in ToolPage.values)
            ListTile(
              leading: Icon(page.icon),
              title: Text(page.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(appBar: AppBar(title: Text(page.label)), body: _page(page)),
              )),
            ),
        ]);
      });
}
