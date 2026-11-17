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
                if (state.bakeryRootId != null) {
                  nav.push(MaterialPageRoute(
                      builder: (_) => OdooMenuScreen(
                          state: state, menuId: state.bakeryRootId!, title: state.bakeryRootName ?? 'Caravan Bakery Suite')));
                  return;
                }
                final all = await state.client.rootMenus();
                if (all.isEmpty) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Your Odoo user can see no menus. Ask an Odoo administrator to check your access.')));
                  return;
                }
                final k = kBakeryMenuKeywords;
                final match = all.where((m) => k.any((w) => m.name.toLowerCase().contains(w))).toList();
                if (match.length == 1) {
                  await state.setBakeryRoot(match.first.id, match.first.name);
                  nav.push(MaterialPageRoute(
                      builder: (_) => OdooMenuScreen(state: state, menuId: match.first.id, title: match.first.name)));
                } else {
                  nav.push(MaterialPageRoute(
                      builder: (_) => _RootPicker(
                            state: state,
                            roots: match.isEmpty ? all : match,
                            note: match.isEmpty
                                ? 'No menu with "bakery" in its name was found. These are all the Odoo menus your user can see. Pick the bakery module:'
                                : 'Several menus match. Pick the bakery module:',
                          )));
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Could not read Odoo menus: $e')));
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

/// Lets the user pick the bakery module's top-level Odoo menu; the choice is remembered.
class _RootPicker extends StatelessWidget {
  final AppState state;
  final List<MenuNode> roots;
  final String note;
  const _RootPicker({required this.state, required this.roots, required this.note});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Choose bakery menu')),
        body: ListView(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(note)),
          for (final r in roots)
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(r.name),
              onTap: () async {
                await state.setBakeryRoot(r.id, r.name);
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => OdooMenuScreen(state: state, menuId: r.id, title: r.name)));
              },
            ),
        ]),
      );
}
