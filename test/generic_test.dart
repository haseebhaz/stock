import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stock_check/odoo/generic.dart';
import 'package:stock_check/odoo/odoo_client.dart';

const formArch = '''
<form>
  <header><field name="state" widget="statusbar"/></header>
  <sheet>
    <field name="name"/>
    <field name="secret" invisible="1"/>
    <field name="qty" readonly="state != 'draft'"/>
    <field name="shelf_life" readonly="1"/>
    <field name="ingredient_ids">
      <list><field name="product_id"/><field name="amount"/><field name="hidden" column_invisible="1"/></list>
    </field>
  </sheet>
</form>''';

void main() {
  test('simple domains are parsed, complex ones ignored', () {
    expect(parseDomain("[('state','=','draft')]"), [['state', '=', 'draft']]);
    expect(parseDomain("[('active','=',True)]"), [['active', '=', true]]);
    expect(parseDomain("[('user_id','=',uid)]"), isEmpty);
    expect(parseDomain(''), isEmpty);
    expect(parseDomain('[]'), isEmpty);
  });

  test('form view: order, hidden fields, readonly hints, line columns', () {
    final f = parseFormArch(formArch);
    expect(f.map((e) => e.name).toList(), ['state', 'name', 'qty', 'shelf_life', 'ingredient_ids']);
    expect(f.firstWhere((e) => e.name == 'name').readonlyInView, false);
    expect(f.firstWhere((e) => e.name == 'qty').readonlyInView, true); // conditional -> safe read-only
    expect(f.firstWhere((e) => e.name == 'shelf_life').readonlyInView, true);
    expect(f.last.subFields, ['product_id', 'amount']); // nested fields are not top-level
  });

  test('list view columns skip hidden/optional', () {
    expect(parseListColumns('<list><field name="a"/><field name="b" optional="hide"/><field name="c" column_invisible="1"/><field name="d"/></list>'), ['a', 'd']);
  });

  test('menu tree and action lookup', () async {
    final mock = MockClient((req) async {
      final p = jsonDecode(req.body)['params'];
      final a = p['args'] as List;
      dynamic result;
      if (p['service'] == 'common') {
        result = 7;
      } else if (a[3] == 'res.users') {
        result = [{'id': 7, 'name': 'T'}];
      } else if (a[3] == 'product.product') {
        result = {};
      } else if (a[3] == 'ir.ui.menu') {
        final dom = (a[5] as List)[0] as List;
        result = (dom[0] as List)[2] == false
            ? [
                {'id': 1, 'name': 'Caravan Bakery Suite', 'action': false, 'child_id': [2, 3]},
                {'id': 9, 'name': 'Sales', 'action': false, 'child_id': [10]},
              ]
            : [
                {'id': 2, 'name': 'Production', 'action': 'ir.actions.act_window,45', 'child_id': []},
                {'id': 3, 'name': 'Reports', 'action': 'ir.actions.report,5', 'child_id': []},
              ];
      } else if (a[3] == 'ir.actions.act_window') {
        result = [{'id': 45, 'res_model': 'bakery.production', 'name': 'Production', 'domain': "[('state','!=','cancel')]"}];
      }
      return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200, headers: {'content-type': 'application/json'});
    });
    final c = OdooClient('https://x', httpClient: mock);
    await c.login('db', 'u', 'k');
    final roots = await c.findRootMenus(['bakery', 'carawan']);
    expect(roots.map((r) => r.name), ['Caravan Bakery Suite']);
    expect(roots.first.hasChildren, true);
    final kids = await c.menuChildren(1);
    expect(kids.length, 2);
    final act = await c.actionInfo(kids.first.action!);
    expect(act!.model, 'bakery.production');
    expect(act.domain, [['state', '!=', 'cancel']]);
    expect(await c.actionInfo(kids.last.action!), isNull); // reports are not supported
  });
}
