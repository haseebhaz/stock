import 'package:flutter/material.dart';
import '../app_state.dart';
import '../config.dart';

class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final r = state.rights;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        _header(context, 'Store'),
        ListTile(
          leading: const Icon(Icons.store),
          title: Text(state.warehouse?.name ?? '-'),
          subtitle: const Text('Change store'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Go back to the root, then show the mandatory store picker.
            Navigator.of(context).popUntil((route) => route.isFirst);
            state.changeStore();
          },
        ),
        const Divider(),
        _header(context, 'Account'),
        ListTile(leading: const Icon(Icons.person), title: Text(state.client.userName ?? '-'), subtitle: Text(state.savedLogin ?? '')),
        ListTile(leading: const Icon(Icons.storage), title: Text(state.savedDb ?? '-'), subtitle: const Text('Database')),
        ListTile(leading: const Icon(Icons.cloud), title: const Text(kOdooUrl), subtitle: const Text('Server')),
        const Divider(),
        _header(context, 'User access rights'),
        _right(Icons.visibility, 'View stock', r.canView, 'Inventory > User'),
        _right(Icons.edit, 'Update stock quantity', r.canAdjust, 'Inventory > Administrator'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text(
            'Rights come from your Odoo user and are changed by an Odoo administrator '
            '(Settings > Users). Without update rights the "Update quantity" button is disabled.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ]),
    );
  }

  Widget _header(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: Theme.of(c).textTheme.titleSmall?.copyWith(color: Theme.of(c).colorScheme.primary)),
      );

  Widget _right(IconData icon, String title, bool? allowed, String odooGroup) {
    final (label, color, mark) = switch (allowed) {
      true => ('Allowed', Colors.green, Icons.check_circle),
      false => ('Not allowed', Colors.red, Icons.cancel),
      null => ('Unknown', Colors.orange, Icons.help),
    };
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('Odoo group: $odooGroup'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(mark, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color)),
      ]),
    );
  }
}
