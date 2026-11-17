import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/generic.dart';
import 'record_form_screen.dart';

/// Generic list of the records of any Odoo model, with search and paging.
class RecordListScreen extends StatefulWidget {
  final AppState state;
  final String model;
  final String title;
  final List<dynamic> domain;
  const RecordListScreen({super.key, required this.state, required this.model, required this.title, this.domain = const []});
  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  static const _page = 40;
  Map<String, FieldDef> _defs = {};
  List<String> _cols = [];
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _more = false, _canCreate = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = widget.state.client;
      _defs = await c.fieldDefs(widget.model);
      _cols = await c.listColumns(widget.model, _defs);
      _canCreate = (await c.hasRight(widget.model, 'create')) != false;
      await _load(reset: true);
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _rows.clear();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.state.client.searchRecords(widget.model, widget.domain, _cols,
          query: _query, offset: _rows.length, limit: _page);
      _rows.addAll(r);
      _more = r.length == _page && _query.isEmpty;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  String _show(Map<String, dynamic> row, String col) {
    final v = row[col];
    if (v == false || v == null) return '';
    if (v is List && v.length == 2 && v[1] is String) return v[1];
    if (v is List) return '${v.length} items';
    final d = _defs[col];
    if (d != null && d.type == 'selection') {
      for (final s in d.selection) {
        if (s[0] == v) return '${s[1]}';
      }
    }
    if (v is double) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return '$v';
  }

  Future<void> _openForm(int? id) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => RecordFormScreen(state: widget.state, model: widget.model, recordId: id, title: widget.title)));
    if (changed == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(onPressed: () => _openForm(null), icon: const Icon(Icons.add), label: const Text('New'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder()),
            onSubmitted: (v) {
              _query = v;
              _load(reset: true);
            },
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(
          child: ListView.separated(
            itemCount: _rows.length + (_more ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == _rows.length) {
                return TextButton(onPressed: _loading ? null : () => _load(), child: const Text('Load more'));
              }
              final r = _rows[i];
              final extra = [for (final c in _cols) if (_show(r, c).isNotEmpty) '${_defs[c]?.label ?? c}: ${_show(r, c)}'];
              return ListTile(
                title: Text('${r['display_name'] ?? r['id']}'),
                subtitle: extra.isEmpty ? null : Text(extra.join('\n')),
                isThreeLine: extra.length > 1,
                onTap: () => _openForm(r['id']),
              );
            },
          ),
        ),
        if (!_loading && _rows.isEmpty && _error == null) const Expanded(child: Center(child: Text('No records.'))),
      ]),
    );
  }
}
