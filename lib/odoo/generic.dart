import 'dart:convert';
import 'package:xml/xml.dart';
import 'odoo_client.dart';

/// One entry of Odoo's own menu tree.
class MenuNode {
  final int id;
  final String name;
  final String? action; // e.g. "ir.actions.act_window,45"
  final bool hasChildren;
  MenuNode(this.id, this.name, this.action, this.hasChildren);
}

class ActionInfo {
  final String model;
  final String name;
  final List<dynamic> domain; // only a simple, literal domain is applied
  ActionInfo(this.model, this.name, this.domain);
}

class FieldDef {
  final String name;
  final String label;
  final String type;
  final List<List<dynamic>> selection;
  final String? relation;
  final bool readonly;
  final bool required;
  FieldDef(this.name, this.label, this.type, this.selection, this.relation, this.readonly, this.required);
}

/// A field as placed in the Odoo form view.
class FormFieldSpec {
  final String name;
  final bool readonlyInView; // readonly="1" or any conditional readonly (we stay safe)
  final List<String> subFields; // columns of an inline line list (recipe lines etc.)
  FormFieldSpec(this.name, this.readonlyInView, this.subFields);
}

/// Odoo domains are Python text. Accept only simple literal ones; otherwise no filter.
List<dynamic> parseDomain(String? s) {
  if (s == null || s.trim().isEmpty || s.trim() == '[]') return [];
  try {
    var j = s
        .replaceAll('(', '[')
        .replaceAll(')', ']')
        .replaceAll('True', 'true')
        .replaceAll('False', 'false')
        .replaceAll("'", '"');
    j = j.replaceAll(RegExp(r',\s*\]'), ']');
    final v = jsonDecode(j);
    return v is List ? v : [];
  } catch (_) {
    return [];
  }
}

bool _flag(String? v) => v == '1' || v == 'True' || v == 'true';

/// Fields of a form view in screen order. Fields inside inline line lists are
/// returned as the [subFields] of their parent field.
List<FormFieldSpec> parseFormArch(String arch) {
  final doc = XmlDocument.parse(arch);
  final out = <FormFieldSpec>[];
  final seen = <String>{};
  for (final f in doc.rootElement.findAllElements('field')) {
    final nested = f.ancestors.whereType<XmlElement>().any((e) => e.name.local == 'field');
    final name = f.getAttribute('name');
    if (nested || name == null || seen.contains(name)) continue;
    if (_flag(f.getAttribute('invisible'))) continue;
    final ro = f.getAttribute('readonly');
    final sub = <String>[];
    for (final child in f.children.whereType<XmlElement>()) {
      if (child.name.local == 'list' || child.name.local == 'tree') {
        for (final c in child.findAllElements('field')) {
          final n = c.getAttribute('name');
          if (n != null && !_flag(c.getAttribute('invisible')) && c.getAttribute('column_invisible') != '1' && c.getAttribute('column_invisible') != 'True') {
            sub.add(n);
          }
        }
      }
    }
    seen.add(name);
    out.add(FormFieldSpec(name, ro != null && ro.isNotEmpty && !(ro == '0' || ro == 'False' || ro == 'false'), sub));
  }
  return out;
}

/// Columns of a list view (used as the summary line of each record).
List<String> parseListColumns(String arch) {
  final doc = XmlDocument.parse(arch);
  final cols = <String>[];
  for (final f in doc.rootElement.findAllElements('field')) {
    final n = f.getAttribute('name');
    if (n == null || cols.contains(n)) continue;
    if (_flag(f.getAttribute('column_invisible')) || _flag(f.getAttribute('invisible'))) continue;
    if (f.getAttribute('optional') == 'hide') continue;
    cols.add(n);
  }
  return cols;
}

extension GenericApi on OdooClient {
  // ---- Odoo menu tree ----------------------------------------------------

  List<MenuNode> _menus(List rows) => [
        for (final m in rows)
          MenuNode(m['id'], m['name'], m['action'] is String ? m['action'] : null, (m['child_id'] as List).isNotEmpty)
      ];

  /// Every top-level menu the logged-in user may see (Odoo hides the others).
  Future<List<MenuNode>> rootMenus() async {
    final r = await exec('ir.ui.menu', 'search_read', [
      [
        ['parent_id', '=', false]
      ]
    ], {'fields': ['name', 'action', 'child_id'], 'order': 'sequence,id'}) as List;
    return _menus(r);
  }

  /// Top-level menus whose name contains one of [keywords].
  Future<List<MenuNode>> findRootMenus(List<String> keywords) async {
    final k = keywords.map((e) => e.toLowerCase()).toList();
    return (await rootMenus()).where((m) => k.any((w) => m.name.toLowerCase().contains(w))).toList();
  }

  Future<List<MenuNode>> menuChildren(int parentId) async {
    final r = await exec('ir.ui.menu', 'search_read', [
      [
        ['parent_id', '=', parentId]
      ]
    ], {'fields': ['name', 'action', 'child_id'], 'order': 'sequence,id'}) as List;
    return _menus(r);
  }

  /// Only window actions (list/form screens of one model) are supported.
  Future<ActionInfo?> actionInfo(String ref) async {
    final parts = ref.split(',');
    if (parts.length != 2 || parts[0] != 'ir.actions.act_window') return null;
    final r = await exec('ir.actions.act_window', 'read', [
      [int.parse(parts[1])],
      ['res_model', 'name', 'domain']
    ]) as List;
    if (r.isEmpty) return null;
    final d = r.first as Map;
    return ActionInfo(d['res_model'], d['name'], parseDomain(d['domain'] is String ? d['domain'] : null));
  }

  // ---- Model structure ---------------------------------------------------

  Future<Map<String, FieldDef>> fieldDefs(String model) async {
    final f = await exec('$model', 'fields_get', [], {
      'attributes': ['string', 'type', 'selection', 'relation', 'readonly', 'required', 'store']
    }) as Map;
    return {
      for (final e in f.entries)
        e.key as String: FieldDef(
          e.key as String,
          (e.value['string'] ?? e.key).toString(),
          e.value['type'] as String,
          [for (final x in (e.value['selection'] ?? []) as List) List<dynamic>.from(x as List)],
          e.value['relation'] as String?,
          e.value['readonly'] == true,
          e.value['required'] == true,
        )
    };
  }

  Future<String?> _arch(String model, String type) async {
    for (final t in type == 'list' ? ['list', 'tree'] : [type]) {
      try {
        final r = await exec(model, 'get_views', [
          [
            [false, t]
          ]
        ], {'options': {}}) as Map;
        final v = (r['views'] as Map)[t];
        if (v != null && v['arch'] is String) return v['arch'];
      } catch (_) {}
    }
    return null;
  }

  Future<List<FormFieldSpec>> formLayout(String model, Map<String, FieldDef> defs) async {
    final arch = await _arch(model, 'form');
    List<FormFieldSpec> out = [];
    if (arch != null) {
      try {
        out = parseFormArch(arch);
      } catch (_) {}
    }
    if (out.isEmpty) {
      // No usable form view: show the simple stored fields.
      out = [
        for (final d in defs.values)
          if (!const ['binary', 'one2many', 'many2many', 'html'].contains(d.type) &&
              !d.name.startsWith('message_') && !d.name.startsWith('activity_') &&
              !const ['id', 'create_uid', 'create_date', 'write_uid', 'write_date', 'display_name'].contains(d.name))
            FormFieldSpec(d.name, true, [])
      ];
    }
    return out.where((f) => defs.containsKey(f.name)).toList();
  }

  Future<List<String>> listColumns(String model, Map<String, FieldDef> defs) async {
    final arch = await _arch(model, 'list');
    var cols = <String>[];
    if (arch != null) {
      try {
        cols = parseListColumns(arch);
      } catch (_) {}
    }
    cols = cols.where((c) => defs.containsKey(c) && defs[c]!.type != 'binary' && defs[c]!.type != 'html').take(4).toList();
    return cols;
  }

  // ---- Records -----------------------------------------------------------

  Future<List<Map<String, dynamic>>> searchRecords(
    String model,
    List<dynamic> domain,
    List<String> fields, {
    String query = '',
    int offset = 0,
    int limit = 40,
  }) async {
    var dom = domain;
    if (query.trim().isNotEmpty) {
      final hits = await exec(model, 'name_search', [], {'name': query.trim(), 'args': domain, 'limit': 200}) as List;
      dom = [
        ['id', 'in', [for (final h in hits) (h as List)[0]]]
      ];
    }
    final r = await exec(model, 'search_read', [dom], {
      'fields': {'display_name', ...fields}.toList(),
      'offset': offset,
      'limit': limit,
    }) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> readRecord(String model, int id, List<String> fields) async {
    final r = await exec(model, 'read', [
      [id],
      {'display_name', ...fields}.toList()
    ]) as List;
    return Map<String, dynamic>.from(r.first as Map);
  }

  /// Rows of a one2many/many2many field. Uses the columns of the form's inline list.
  Future<List<Map<String, dynamic>>> relatedRows(String relation, List ids, List<String> columns) async {
    if (ids.isEmpty) return [];
    final r = await exec(relation, 'read', [
      ids,
      {'display_name', ...columns}.toList()
    ]) as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<List<dynamic>>> nameSearch(String model, String q) async {
    final r = await exec(model, 'name_search', [], {'name': q, 'limit': 30}) as List;
    return [for (final x in r) List<dynamic>.from(x as List)];
  }

  /// true/false, or null if Odoo could not tell (the server still enforces rights).
  Future<bool?> hasRight(String model, String op) async {
    try {
      return await exec(model, 'check_access_rights', [op], {'raise_exception': false}) == true;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> defaults(String model, List<String> fields) async {
    try {
      return Map<String, dynamic>.from(await exec(model, 'default_get', [fields]) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> writeRecord(String model, int id, Map<String, dynamic> vals) async {
    await exec(model, 'write', [
      [id],
      vals
    ]);
  }

  Future<int> createRecord(String model, Map<String, dynamic> vals) async {
    final r = await exec(model, 'create', [vals]);
    return r is List ? r.first as int : r as int;
  }
}
