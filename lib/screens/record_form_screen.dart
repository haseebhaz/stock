import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/generic.dart';

/// Generic form for any Odoo record. Opens read-only; "Edit" is offered only when
/// Odoo says the user may write. Odoo still enforces its own rules on save.
class RecordFormScreen extends StatefulWidget {
  final AppState state;
  final String model;
  final int? recordId; // null = new record
  final String title;
  const RecordFormScreen({super.key, required this.state, required this.model, required this.recordId, required this.title});
  @override
  State<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends State<RecordFormScreen> {
  Map<String, FieldDef> _defs = {};
  List<FormFieldSpec> _layout = [];
  Map<String, dynamic> _rec = {};
  final Map<String, dynamic> _changes = {};
  final Map<String, List<Map<String, dynamic>>> _lines = {};
  bool _loading = true, _editing = false, _canWrite = false, _saving = false;
  String? _error;

  bool get _isNew => widget.recordId == null;
  static const _plain = {'char', 'text', 'integer', 'float', 'monetary', 'boolean', 'selection', 'date', 'datetime', 'many2one'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = widget.state.client;
      _defs = await c.fieldDefs(widget.model);
      _layout = await c.formLayout(widget.model, _defs);
      final names = [for (final f in _layout) f.name];
      if (_isNew) {
        _rec = await c.defaults(widget.model, names);
        _canWrite = (await c.hasRight(widget.model, 'create')) != false;
        _editing = true;
      } else {
        _rec = await c.readRecord(widget.model, widget.recordId!, names);
        _canWrite = (await c.hasRight(widget.model, 'write')) != false;
        for (final f in _layout) {
          final d = _defs[f.name]!;
          if ((d.type == 'one2many' || d.type == 'many2many') && d.relation != null) {
            final ids = (_rec[f.name] as List?) ?? [];
            _lines[f.name] = await c.relatedRows(
                d.relation!, ids, f.subFields.isEmpty ? [] : f.subFields.take(5).toList());
          }
        }
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  dynamic _value(String n) => _changes.containsKey(n) ? _changes[n] : _rec[n];

  bool _editable(FormFieldSpec f) {
    final d = _defs[f.name]!;
    return _editing && _canWrite && !f.readonlyInView && !d.readonly && _plain.contains(d.type);
  }

  Future<void> _save() async {
    for (final f in _layout) {
      final d = _defs[f.name]!;
      if (d.required && _editable(f)) {
        final v = _value(f.name);
        if (v == null || v == false || (v is String && v.trim().isEmpty)) {
          if (d.type != 'boolean' && d.type != 'integer' && d.type != 'float') {
            setState(() => _error = '"${d.label}" is required.');
            return;
          }
        }
      }
    }
    if (_changes.isEmpty && !_isNew) {
      setState(() => _editing = false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = widget.state.client;
      if (_isNew) {
        final vals = {..._rec, ..._changes}..removeWhere((k, v) => !_defs.containsKey(k) || !_plain.contains(_defs[k]!.type) || _defs[k]!.readonly);
        await c.createRecord(widget.model, _toOdoo(vals));
      } else {
        await c.writeRecord(widget.model, widget.recordId!, _toOdoo(_changes));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _toOdoo(Map<String, dynamic> v) {
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      final t = _defs[k]?.type;
      if (t == 'many2one') {
        out[k] = val is List ? val[0] : (val == null || val == false ? false : val);
      } else if (t == 'datetime' && val is DateTime) {
        out[k] = _fmtDt(val.toUtc());
      } else {
        out[k] = val;
      }
    });
    return out;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String _fmtDt(DateTime d) => '${_fmtDate(d)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

  String _display(FormFieldSpec f) {
    final d = _defs[f.name]!;
    final v = _value(f.name);
    if (v == null || v == false) return d.type == 'boolean' ? 'No' : '';
    switch (d.type) {
      case 'many2one':
        return v is List ? '${v[1]}' : '$v';
      case 'selection':
        for (final s in d.selection) {
          if (s[0] == v) return '${s[1]}';
        }
        return '$v';
      case 'boolean':
        return v == true ? 'Yes' : 'No';
      case 'datetime':
        final dt = v is DateTime ? v : DateTime.tryParse('${v}Z')?.toLocal();
        return dt == null ? '$v' : _fmtDt(dt);
      case 'html':
        return '$v'.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      case 'binary':
        return '(file)';
      default:
        if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
        return '$v';
    }
  }

  Widget _field(FormFieldSpec f) {
    final d = _defs[f.name]!;
    final label = d.label + (d.required && _editable(f) ? ' *' : '');
    if (d.type == 'one2many' || d.type == 'many2many') return _linesBlock(f, d);
    if (!_editable(f)) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        subtitle: Text(_display(f).isEmpty ? '-' : _display(f), style: const TextStyle(fontSize: 16, color: null)),
      );
    }
    final pad = const EdgeInsets.symmetric(vertical: 6);
    switch (d.type) {
      case 'boolean':
        return SwitchListTile(
            contentPadding: EdgeInsets.zero, title: Text(label), value: _value(f.name) == true,
            onChanged: (v) => setState(() => _changes[f.name] = v));
      case 'selection':
        final cur = _value(f.name);
        return Padding(
          padding: pad,
          child: DropdownButtonFormField<dynamic>(
            initialValue: d.selection.any((s) => s[0] == cur) ? cur : null,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            items: [for (final s in d.selection) DropdownMenuItem(value: s[0], child: Text('${s[1]}'))],
            onChanged: (v) => setState(() => _changes[f.name] = v),
          ),
        );
      case 'date':
        return _pickerTile(label, _display(f), () async {
          final cur = DateTime.tryParse('${_value(f.name) is String ? _value(f.name) : ''}') ?? DateTime.now();
          final p = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (p != null) setState(() => _changes[f.name] = _fmtDate(p));
        });
      case 'datetime':
        return _pickerTile(label, _display(f), () async {
          final v = _value(f.name);
          final cur = v is DateTime ? v : (DateTime.tryParse('${v}Z')?.toLocal() ?? DateTime.now());
          final day = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (day == null || !mounted) return;
          final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(cur));
          if (t == null) return;
          setState(() => _changes[f.name] = DateTime(day.year, day.month, day.day, t.hour, t.minute));
        });
      case 'many2one':
        return _pickerTile(label, _display(f), () => _pickRelation(f, d));
      default:
        final numeric = d.type == 'integer' || d.type == 'float' || d.type == 'monetary';
        final cur = _value(f.name);
        return Padding(
          padding: pad,
          child: TextFormField(
            initialValue: (cur == null || cur == false) ? '' : (cur is double && cur == cur.roundToDouble() ? cur.toInt().toString() : '$cur'),
            keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
            maxLines: d.type == 'text' ? 4 : 1,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            onChanged: (s) {
              if (numeric) {
                final n = s.trim().isEmpty ? 0 : (d.type == 'integer' ? int.tryParse(s) : double.tryParse(s.replaceAll(',', '.')));
                if (n != null) _changes[f.name] = n;
              } else {
                _changes[f.name] = s;
              }
            },
          ),
        );
    }
  }

  Widget _pickerTile(String label, String value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(value.isEmpty ? ' ' : value),
          ),
        ),
      );

  Future<void> _pickRelation(FormFieldSpec f, FieldDef d) async {
    if (d.relation == null) return;
    final picked = await showDialog<List<dynamic>?>(
      context: context,
      builder: (_) => _RelationPicker(state: widget.state, model: d.relation!, title: d.label),
    );
    if (picked != null) setState(() => _changes[f.name] = picked.isEmpty ? false : picked);
  }

  Widget _linesBlock(FormFieldSpec f, FieldDef d) {
    final rows = _lines[f.name] ?? [];
    final subs = f.subFields.take(5).toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d.label} (${rows.length})', style: Theme.of(context).textTheme.titleSmall),
          const Divider(),
          if (rows.isEmpty) const Text('-'),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(subs.isEmpty
                  ? '${r['display_name']}'
                  : subs.map((c) => _cell(r[c])).where((s) => s.isNotEmpty).join('  ·  ')),
            ),
          if (_editing) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Lines can be changed in Odoo on a PC.', style: TextStyle(color: Colors.grey, fontSize: 12))),
        ]),
      ),
    );
  }

  String _cell(dynamic v) {
    if (v == null || v == false) return '';
    if (v is List && v.length == 2 && v[1] is String) return v[1];
    if (v is List) return '${v.length}';
    if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew ? 'New · ${widget.title}' : '${_rec['display_name'] ?? widget.title}';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (!_loading && !_editing && _canWrite)
          TextButton.icon(onPressed: () => setState(() => _editing = true), icon: const Icon(Icons.edit), label: const Text('Edit')),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              for (final f in _layout) _field(f),
              if (_editing) ...[
                const SizedBox(height: 8),
                const Text('Edits skip Odoo\'s automatic calculations and screen locking. Odoo\'s access rights and validation still apply.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Padding(padding: const EdgeInsets.all(14), child: Text(_saving ? 'Saving...' : 'Save')),
                ),
              ],
            ]),
    );
  }
}

class _RelationPicker extends StatefulWidget {
  final AppState state;
  final String model;
  final String title;
  const _RelationPicker({required this.state, required this.model, required this.title});
  @override
  State<_RelationPicker> createState() => _RelationPickerState();
}

class _RelationPickerState extends State<_RelationPicker> {
  List<List<dynamic>> _hits = [];
  bool _busy = false;
  String? _error;

  Future<void> _search(String q) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _hits = await widget.state.client.nameSearch(widget.model, q);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(children: [
          TextField(decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)), onSubmitted: _search),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView(children: [
              for (final h in _hits) ListTile(dense: true, title: Text('${h[1]}'), onTap: () => Navigator.pop(context, h)),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, <dynamic>[]), child: const Text('Clear')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
