import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stock_check/odoo/models.dart';
import 'package:stock_check/odoo/odoo_client.dart';

/// Fake Odoo: records calls and answers the few RPCs the app uses.
class FakeOdoo {
  final calls = <Map<String, dynamic>>[];
  late final MockClient client = MockClient((req) async {
    final p = jsonDecode(req.body)['params'];
    final args = p['args'] as List;
    dynamic result;
    if (p['service'] == 'db') {
      result = ['mydb'];
    } else if (p['service'] == 'common') {
      result = args[2] == 'goodkey' ? 7 : false;
    } else {
      final model = args[3], method = args[4];
      final a = args[5] as List, kw = args[6] as Map;
      calls.add({'model': model, 'method': method, 'args': a, 'kw': kw});
      switch ('$model.$method') {
        case 'res.users.read':
          result = [{'id': 7, 'name': 'Tester'}];
        case 'product.product.fields_get':
          result = {
            'name': {'string': 'Name', 'type': 'char', 'store': true},
            'x_rack': {'string': 'Rack Location', 'type': 'char', 'store': true},
          };
        case 'product.product.search':
          final code = ((a[0] as List)[0] as List)[2];
          result = code == '111' ? [5] : [];
        case 'product.packaging.search_read':
          final code = ((a[0] as List)[0] as List)[2];
          result = code == 'CTN9'
              ? [{'id': 1, 'name': 'Carton', 'qty': 12.0, 'product_id': [5, 'Cola']}]
              : [];
        case 'product.product.read':
          result = [{
            'id': 5, 'name': 'Cola', 'uom_id': [1, 'Units'], 'barcode': '111',
            'tracking': 'none', 'qty_available': 30.0, 'free_qty': 25.0, 'x_rack': 'A-12',
          }];
        case 'stock.quant.search_read':
          result = [{'id': 1, 'quantity': 20.0}]; // 10 more sits in sub-locations
        case 'product.product.search_read':
          result = [
            {'id': 5, 'name': 'Cola 330ml', 'barcode': '111', 'default_code': 'C1', 'uom_id': [1, 'Units'], 'qty_available': 30.0},
            {'id': 6, 'name': 'Cola Zero', 'barcode': false, 'default_code': false, 'uom_id': [1, 'Units'], 'qty_available': 4.0},
          ];
        case 'res.users.has_group':
          // Odoo variant that takes the group name only (acts on the current user)
          result = a.first == 'stock.group_stock_manager' ? false : true;
        case 'stock.quant.create':
          result = [99];
        default:
          result = true;
      }
    }
    return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200,
        headers: {'content-type': 'application/json'});
  });
}

void main() {
  final wh = Warehouse(3, 'Main Store', 'MS', 42);

  Future<(OdooClient, FakeOdoo)> loggedIn() async {
    final f = FakeOdoo();
    final c = OdooClient('https://x', httpClient: f.client);
    await c.login('mydb', 'u', 'goodkey');
    return (c, f);
  }

  test('lists databases and rejects a bad key', () async {
    final f = FakeOdoo();
    final c = OdooClient('https://x', httpClient: f.client);
    expect(await c.listDatabases(), ['mydb']);
    expect(() => c.login('mydb', 'u', 'bad'), throwsA(isA<OdooException>()));
  });

  test('detects rack location field and reads qty in selected warehouse', () async {
    final (c, f) = await loggedIn();
    expect(c.rackField, 'x_rack');
    final r = (await c.lookup('111', wh))!;
    expect(r.rackLocation, 'A-12');
    expect(r.onHand, 30);
    expect(r.packaging, isNull);
    final read = f.calls.lastWhere((x) => x['method'] == 'read' && x['model'] == 'product.product');
    expect(read['kw']['context']['warehouse_id'], 3);
  });

  test('packaging barcode resolves to item with pack quantity', () async {
    final (c, _) = await loggedIn();
    final r = (await c.lookup('CTN9', wh))!;
    expect(r.name, 'Cola');
    expect(r.packaging!.qty, 12);
  });

  test('unknown barcode returns null', () async {
    final (c, _) = await loggedIn();
    expect(await c.lookup('nope', wh), isNull);
  });

  test('adjust applies only the difference to the main location', () async {
    final (c, f) = await loggedIn();
    final r = (await c.lookup('111', wh))!;
    // Warehouse total 30 (20 main + 10 sub). Counted 25 -> main location target 15.
    await c.adjust(item: r, wh: wh, newQty: 25, reason: 'Miscount');
    final create = f.calls.firstWhere((x) => x['method'] == 'create');
    final vals = (create['args'][0] as List)[0];
    expect(vals['inventory_quantity'], 15.0);
    expect(vals['location_id'], 42);
    expect(create['kw']['context']['inventory_mode'], true);
    expect(f.calls.any((x) => x['method'] == 'action_apply_inventory'), true);
  });

  test('adjust refuses to go below stock held in main location', () async {
    final (c, _) = await loggedIn();
    final r = (await c.lookup('111', wh))!;
    expect(() => c.adjust(item: r, wh: wh, newQty: 5, reason: 'Miscount'),
        throwsA(isA<OdooException>())); // target would be -5
  });

  test('search by name returns hits and requires every word', () async {
    final (c, f) = await loggedIn();
    final hits = await c.searchByName('cola  zero', wh);
    expect(hits.length, 2);
    expect(hits[1].barcode, isNull);
    final call = f.calls.lastWhere((x) => x['method'] == 'search_read' && x['model'] == 'product.product');
    final domain = (call['args'] as List)[0] as List;
    expect(domain.where((e) => e == '&').length, 1); // two words -> one AND
    expect(call['kw']['context']['warehouse_id'], 3);
    expect(await c.searchByName('   ', wh), isEmpty);
  });

  test('access rights: stock user yes, administrator no', () async {
    final (c, _) = await loggedIn();
    final r = await c.accessRights();
    expect(r.canView, true);
    expect(r.canAdjust, false);
  });
}
