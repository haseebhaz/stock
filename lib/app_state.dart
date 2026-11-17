import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'odoo/models.dart';
import 'odoo/odoo_client.dart';

class AppState extends ChangeNotifier {
  final OdooClient client = OdooClient(kOdooUrl);
  final _secure = const FlutterSecureStorage();
  bool ready = false;
  bool loggedIn = false;
  Warehouse? warehouse;
  List<Warehouse> warehouses = [];
  int? lastWarehouseId;
  String? savedDb, savedLogin;
  AccessRights rights = const AccessRights();
  final List<String> history = [];

  /// Updating is allowed unless Odoo says this user is not an Inventory Administrator.
  bool get canAdjust => rights.canAdjust != false;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    savedDb = p.getString('db');
    savedLogin = p.getString('login');
    lastWarehouseId = p.getInt('warehouse');
    final key = await _secure.read(key: 'key');
    if (savedDb != null && savedLogin != null && key != null) {
      try {
        await client.login(savedDb!, savedLogin!, key);
        loggedIn = true;
        await loadWarehouses();
        rights = await client.accessRights();
        // Restored session: keep the last store if it still exists.
        warehouse = warehouses.where((w) => w.id == lastWarehouseId).firstOrNull;
      } catch (_) {
        loggedIn = false;
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login(String db, String user, String key) async {
    await client.login(db, user, key);
    final p = await SharedPreferences.getInstance();
    await p.setString('db', db);
    await p.setString('login', user);
    await _secure.write(key: 'key', value: key);
    savedDb = db;
    savedLogin = user;
    loggedIn = true;
    warehouse = null; // store selection is mandatory after every explicit login
    await loadWarehouses();
    rights = await client.accessRights();
    notifyListeners();
  }

  Future<void> loadWarehouses() async {
    warehouses = await client.warehouses();
  }

  Future<void> selectWarehouse(Warehouse w) async {
    warehouse = w;
    lastWarehouseId = w.id;
    final p = await SharedPreferences.getInstance();
    await p.setInt('warehouse', w.id);
    notifyListeners();
  }

  /// Back to the store picker (scanning is locked until a store is chosen).
  void changeStore() {
    warehouse = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _secure.delete(key: 'key');
    loggedIn = false;
    warehouse = null;
    notifyListeners();
  }

  void addHistory(String line) {
    history.insert(0, line);
    if (history.length > 50) history.removeLast();
  }
}
