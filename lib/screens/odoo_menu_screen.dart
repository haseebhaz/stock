import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/generic.dart';
import 'record_list_screen.dart';

/// Shows one level of Odoo's menu tree. Entries with a window action open the
/// record list; entries with sub-menus open another level.
class OdooMenuScreen extends StatelessWidget {
  final AppState state;
  final int menuId;
  final String title;
  const OdooMenuScreen({super.key, required this.state, required this.menuId, required this.title});

  Future<void> _open(BuildContext context, MenuNode m) async {
    final nav = Navigator.of(context);
    if (m.hasChildren) {
      nav.push(MaterialPageRoute(builder: (_) => OdooMenuScreen(state: state, menuId: m.id, title: m.name)));
      return;
    }
    if (m.action == null) return;
    try {
      final a = await state.client.actionInfo(m.action!);
      if (a == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This menu entry is not available in the app (use Odoo on a PC).')));
        }
        return;
      }
      nav.push(MaterialPageRoute(
          builder: (_) => RecordListScreen(state: state, model: a.model, title: m.name, domain: a.domain)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<List<MenuNode>>(
        future: state.client.menuChildren(menuId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('${snap.error}')));
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('No menu entries available for your user.'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = items[i];
              final usable = m.hasChildren || (m.action ?? '').startsWith('ir.actions.act_window,');
              return ListTile(
                leading: Icon(m.hasChildren ? Icons.folder_open : Icons.list_alt),
                title: Text(m.name),
                subtitle: usable ? null : const Text('Not available in the app'),
                enabled: usable,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, m),
              );
            },
          );
        },
      ),
    );
  }
}
