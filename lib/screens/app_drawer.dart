import 'package:flutter/material.dart';
import '../app_state.dart';
import 'about_screen.dart';
import 'count_screen.dart';
import 'dashboard_screen.dart';
import 'odoo_menu_screen.dart';
import '../config.dart';
import '../odoo/generic.dart';
import 'settings_screen.dart';

/// The 3-line menu.
class AppDrawer extends StatelessWidget {
  final AppState state;
  const AppDrawer({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(children: [
          UserAccountsDrawerHeader(
            accountName: Text(state.client.userName ?? ''),
            accountEmail: Text('Store: ${state.warehouse?.name ?? '-'}'),
            currentAccountPicture: const CircleAvatar(child: Icon(Icons.person, size: 36)),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check),
            title: const Text('Stock count'),
            subtitle: state.count != null ? Text('In progress: ${state.count!.name}') : null,
            onTap: () {
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => CountScreen(state: state)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.insights),
            title: const Text('Consumption dashboard'),
            onTap: () {
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => DashboardScreen(state: state)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.bakery_dining),
            title: const Text('Caravan Bakery Suite'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              try {
                final roots = await state.client.findRootMenus(kBakeryMenuKeywords);
                if (roots.isEmpty) {
                  messenger.showSnackBar(const SnackBar(content: Text('No bakery menu found for your Odoo user.')));
                  return;
                }
                nav.push(MaterialPageRoute(
                    builder: (_) => roots.length == 1
                        ? OdooMenuScreen(state: state, menuId: roots.first.id, title: roots.first.name)
                        : _RootPicker(state: state, roots: roots)));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e')));
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              nav.pop(); // close drawer
              nav.push(MaterialPageRoute(builder: (_) => SettingsScreen(state: state)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () {
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: () {
              nav.pop();
              state.logout();
            },
          ),
        ]),
      ),
    );
  }
}

/// Shown only if several top-level menus match the bakery keywords.
class _RootPicker extends StatelessWidget {
  final AppState state;
  final List<MenuNode> roots;
  const _RootPicker({required this.state, required this.roots});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Caravan Bakery Suite')),
        body: ListView(children: [
          for (final r in roots)
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(r.name),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OdooMenuScreen(state: state, menuId: r.id, title: r.name))),
            ),
        ]),
      );
}
