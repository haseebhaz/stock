import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Talks to Odoo 18's built-in JSON-RPC API (/jsonrpc). No custom module needed.
class OdooClient {
  final String baseUrl;
  final http.Client _http;
  String? db;
  int? uid;
  String? _key;
  String? userName;
  String? rackField; // technical name of the "Rack location" field, if found
  int _id = 0;

  OdooClient(this.baseUrl, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Future<dynamic> _call(String service, String method, List args) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/jsonrpc'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'call',
            'id': ++_id,
            'params': {'service': service, 'method': method, 'args': args},
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw OdooException('Server error (HTTP ${res.statusCode})');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body['error'] != null) {
      final data = body['error']['data'];
      throw OdooException(
          (data is Map ? data['message'] : null) ?? body['error']['message'] ?? 'Unknown error');
    }
    return body['result'];
  }

  /// Generic call used by the Odoo-menu browser (lib/odoo/generic.dart).
  Future<dynamic> exec(String model, String method, List args, [Map<String, dynamic>? kwargs]) =>
      _exec(model, method, args, kwargs);

  Future<dynamic> _exec(String model, String method, List args,
      [Map<String, dynamic>? kwargs]) {
    return _call('object', 'execute_kw',
        [db, uid, _key, model, method, args, kwargs ?? {}]);
  }

  // ---- Login -------------------------------------------------------------

  Future<List<String>> listDatabases() async {
    final r = await _call('db', 'list', []);
    return List<String>.from(r as List);
  }

  /// [apiKey] may be an Odoo API key (recommended) or the account password.
  Future<void> login(String database, String login, String apiKey) async {
    final r = await _call('common', 'authenticate', [database, login, apiKey, {}]);
    if (r == false || r == null) {
      throw OdooException('Wrong login or API key for this database.');
    }
    db = database;
    uid = r as int;
    _key = apiKey;
    final u = await _exec('res.users', 'read', [
      [uid],
      ['name']
    ]);
    userName = (u as List).first['name'] as String;
    await _detectRackField();
  }

  /// The "Rack location" field is a custom field; find it by its label.
  Future<void> _detectRackField() async {
    try {
      final f = await _exec('product.product', 'fields_get', [],
          {'attributes': ['string', 'type', 'store']}) as Map;
      for (final e in f.entries) {
        final label = (e.value['string'] ?? '').toString().toLowerCase();
        final type = e.value['type'];
        if (label.contains('rack') &&
            (type == 'char' || type == 'text' || type == 'many2one') &&
            e.value['store'] != false) {
          rackField = e.key as String;
          return;
        }
      }
    } catch (_) {
      rackField = null;
    }
  }

  // ---- Warehouses --------------------------------------------------------

  Future<List<Warehouse>> warehouses() async {
    final r = await _exec('stock.warehouse', 'search_read', [[]],
        {'fields': ['name', 'code', 'lot_stock_id', 'view_location_id'], 'order': 'name'}) as List;
    return r
        .map((w) => Warehouse(
            w['id'], w['name'], w['code'] ?? '', (w['lot_stock_id'] as List)[0],
            viewLocationId: w['view_location_id'] is List ? (w['view_location_id'] as List)[0] : 0))
        .toList();
  }

  // ---- Lookup ------------------------------------------------------------

  /// Finds an item by item barcode first, then by packaging barcode.
  Future<StockResult?> lookup(String code, Warehouse wh) async {
    code = code.trim();
    if (code.isEmpty) return null;
    Packaging? pack;
    int? productId;

    final p = await _exec('product.product', 'search', [
      [
        ['barcode', '=', code]
      ]
    ], {'limit': 1}) as List;
    if (p.isNotEmpty) {
      productId = p.first as int;
    } else {
      final pk = await _exec('product.packaging', 'search_read', [
        [
          ['barcode', '=', code]
        ]
      ], {'fields': ['name', 'qty', 'product_id'], 'limit': 1}) as List;
      if (pk.isEmpty) return null;
      pack = Packaging(pk.first['id'], pk.first['name'], (pk.first['qty'] as num).toDouble());
      productId = (pk.first['product_id'] as List)[0] as int;
    }
    return _result(productId, code, pack, wh);
  }

  /// Reloads an item (e.g. after an adjustment) keeping the scanned packaging.
  Future<StockResult> refresh(StockResult old, Warehouse wh) =>
      _result(old.productId, old.scannedCode, old.packaging, wh);

  /// Opens an item picked from a name-search list.
  Future<StockResult> byProductId(int id, Warehouse wh) => _result(id, '', null, wh);

  Future<StockResult> _result(int productId, String code, Packaging? pack, Warehouse wh) async {
    final fields = [
      'name', 'uom_id', 'barcode', 'tracking', 'qty_available', 'free_qty',
      if (rackField != null) rackField!,
    ];
    final r = await _exec('product.product', 'read', [
      [productId],
      fields
    ], {'context': {'warehouse_id': wh.id}}) as List;
    final d = r.first as Map;
    String? rack;
    if (rackField != null) {
      final v = d[rackField];
      rack = v is List ? v[1]?.toString() : (v is String && v.isNotEmpty ? v : null);
    }
    return StockResult(
      productId: productId,
      name: d['name'],
      uom: (d['uom_id'] as List)[1],
      itemBarcode: d['barcode'] is String ? d['barcode'] : null,
      scannedCode: code,
      packaging: pack,
      onHand: (d['qty_available'] as num).toDouble(),
      available: (d['free_qty'] as num).toDouble(),
      rackLocation: rack,
      tracked: (d['tracking'] ?? 'none') != 'none',
    );
  }

  /// Search by item name (every typed word must appear) or internal reference.
  Future<List<ProductHit>> searchByName(String query, Warehouse wh) async {
    final words = query.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];
    final conds = [for (final w in words) ['name', 'ilike', w]];
    final domain = [
      '|',
      ['default_code', 'ilike', query.trim()],
      ...List.filled(conds.length - 1, '&'),
      ...conds,
    ];
    final r = await _exec('product.product', 'search_read', [domain], {
      'fields': ['name', 'barcode', 'default_code', 'uom_id', 'qty_available'],
      'limit': 30,
      'order': 'name',
      'context': {'warehouse_id': wh.id},
    }) as List;
    return r
        .map((d) => ProductHit(
              d['id'],
              d['name'],
              d['barcode'] is String ? d['barcode'] : null,
              d['default_code'] is String ? d['default_code'] : null,
              (d['uom_id'] as List)[1],
              (d['qty_available'] as num).toDouble(),
            ))
        .toList();
  }

  // ---- Other stores ------------------------------------------------------

  /// On-hand quantity of one item in every warehouse (read-only).
  Future<List<StoreStock>> stockInAllStores(int productId, List<Warehouse> all) {
    return Future.wait(all.map((w) async {
      final r = await _exec('product.product', 'read', [
        [productId],
        ['qty_available']
      ], {'context': {'warehouse_id': w.id}}) as List;
      return StoreStock(w.name, ((r.first as Map)['qty_available'] as num).toDouble());
    }));
  }

  // ---- Dashboard ---------------------------------------------------------

  static String _odooDate(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}:${t(d.second)}';
  }

  /// Items that left the store (to customers or to production) in the last
  /// [days] days, fastest-moving first, with the current stock for each.
  Future<List<ConsumptionRow>> consumption(Warehouse wh, int days, {int limit = 100}) async {
    if (wh.viewLocationId == 0) throw OdooException('Store location is unknown.');
    final from = DateTime.now().toUtc().subtract(Duration(days: days));
    final domain = [
      ['state', '=', 'done'],
      ['date', '>=', _odooDate(from)],
      ['location_id', 'child_of', wh.viewLocationId],
      ['location_dest_id.usage', 'in', ['customer', 'production']],
    ];
    final groups = await _exec('stock.move', 'read_group', [
      domain,
      ['product_qty:sum'],
      ['product_id']
    ], {'orderby': 'product_qty desc', 'limit': limit, 'lazy': false}) as List;
    if (groups.isEmpty) return [];
    final ids = [for (final g in groups) (g['product_id'] as List)[0] as int];
    final prods = await _exec('product.product', 'read', [
      ids,
      ['name', 'uom_id', 'qty_available']
    ], {'context': {'warehouse_id': wh.id}}) as List;
    final byId = {for (final p in prods) p['id'] as int: p};
    return [
      for (final g in groups)
        if (byId[(g['product_id'] as List)[0]] != null)
          ConsumptionRow(
            (g['product_id'] as List)[0],
            byId[(g['product_id'] as List)[0]]['name'],
            (byId[(g['product_id'] as List)[0]]['uom_id'] as List)[1],
            (g['product_qty'] as num).toDouble(),
            (byId[(g['product_id'] as List)[0]]['qty_available'] as num).toDouble(),
            days,
          ),
    ];
  }

  // ---- Access rights -----------------------------------------------------

  /// Reads what the logged-in user may do in Odoo's Inventory app.
  Future<AccessRights> accessRights() async {
    Future<bool?> has(String group) async {
      for (final args in [
        [group],
        [
          [uid],
          group
        ]
      ]) {
        try {
          return (await _exec('res.users', 'has_group', args)) == true;
        } catch (_) {}
      }
      return null;
    }

    final manager = await has('stock.group_stock_manager');
    final user = await has('stock.group_stock_user');
    return AccessRights(
      canView: (user == null && manager == null) ? null : (user == true || manager == true),
      canAdjust: manager,
    );
  }

  // ---- Adjust ------------------------------------------------------------

  /// Sets the warehouse on-hand quantity of an item to [newQty] using a standard
  /// Odoo inventory adjustment on the warehouse's main stock location.
  Future<void> adjust({
    required StockResult item,
    required Warehouse wh,
    required double newQty,
    required String reason,
  }) async {
    if (item.tracked) {
      throw OdooException('Lot/serial tracked items are not supported.');
    }
    if (newQty < 0) throw OdooException('Quantity cannot be negative.');

    // Quantity currently held directly in the main stock location.
    final q = await _exec('stock.quant', 'search_read', [
      [
        ['product_id', '=', item.productId],
        ['location_id', '=', wh.stockLocationId],
      ]
    ], {'fields': ['quantity']}) as List;
    final locQty = q.fold<double>(0, (s, e) => s + (e['quantity'] as num).toDouble());

    // Warehouse total may include sub-locations; apply only the difference here.
    final target = locQty + (newQty - item.onHand);
    if (target < -0.00001) {
      throw OdooException(
          'Cannot reduce below the stock held in the main location (${_fmt(locQty)}).');
    }

    final ctx = {
      'inventory_mode': true,
      'inventory_name': 'Stock Check App: $reason (${userName ?? ''})',
    };
    final ids = await _exec('stock.quant', 'create', [
      [
        {
          'product_id': item.productId,
          'location_id': wh.stockLocationId,
          'inventory_quantity': target,
        }
      ]
    ], {'context': ctx}) as List;
    await _exec('stock.quant', 'action_apply_inventory', [ids], {'context': ctx});
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
