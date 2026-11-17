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
        {'fields': ['name', 'code', 'lot_stock_id'], 'order': 'name'}) as List;
    return r
        .map((w) => Warehouse(
            w['id'], w['name'], w['code'] ?? '', (w['lot_stock_id'] as List)[0]))
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
