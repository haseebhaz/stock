import 'package:flutter/material.dart';
import '../app_state.dart';
import 'about_screen.dart';
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
