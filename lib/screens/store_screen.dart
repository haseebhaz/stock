import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/models.dart';

/// Mandatory store (warehouse) selection. No back button, no way around it.
class StoreScreen extends StatelessWidget {
  final AppState state;
  const StoreScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Select store'),
          actions: [TextButton(onPressed: state.logout, child: const Text('Log out'))],
        ),
        body: state.warehouses.isEmpty
            ? const Center(child: Text('No warehouses available for this user.'))
            : ListView(children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Choose the store you are working in. Scanning stays locked until you do.'),
                ),
                for (final Warehouse w in state.warehouses)
                  ListTile(
                    leading: Icon(w.id == state.lastWarehouseId ? Icons.history : Icons.store),
                    title: Text(w.name, style: const TextStyle(fontSize: 18)),
                    subtitle: Text(w.id == state.lastWarehouseId ? '${w.code} · last used' : w.code),
                    onTap: () => state.selectWarehouse(w),
                  ),
              ]),
      ),
    );
  }
}
