import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/models.dart';
import 'adjust_screen.dart';
import 'app_drawer.dart';

String fmtQty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');

class ScanScreen extends StatefulWidget {
  final AppState state;
  const ScanScreen({super.key, required this.state});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  StockResult? _item;
  List<ProductHit> _hits = [];
  String? _message;
  bool _busy = false;
  bool _softKeyboard = false;

  Warehouse get wh => widget.state.warehouse!;

  /// Barcode first; if no barcode matches, treat the text as an item name.
  Future<void> _scan(String code) async {
    code = code.trim();
    _ctrl.clear();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
      _hits = [];
    });
    try {
      final r = await widget.state.client.lookup(code, wh);
      if (r != null) {
        setState(() => _item = r);
      } else {
        final hits = await widget.state.client.searchByName(code, wh);
        if (hits.length == 1) {
          final one = await widget.state.client.byProductId(hits.first.id, wh);
          setState(() => _item = one);
        } else {
          setState(() {
            _item = null;
            _hits = hits;
            if (hits.isEmpty) _message = 'No item found for: $code';
          });
        }
      }
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  Future<void> _openHit(ProductHit h) async {
    setState(() => _busy = true);
    try {
      final r = await widget.state.client.byProductId(h.id, wh);
      setState(() {
        _item = r;
        _hits = [];
      });
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  Future<void> _adjust() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => AdjustScreen(state: widget.state, item: _item!, wh: wh)));
    if (changed == true) {
      try {
        final r = await widget.state.client.refresh(_item!, wh);
        setState(() => _item = r);
      } catch (e) {
        setState(() => _message = '$e');
      }
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    return Scaffold(
      drawer: AppDrawer(state: widget.state),
      appBar: AppBar(
        title: Text('Store: ${wh.name}'),
        actions: [
          IconButton(
              tooltip: 'Recent changes',
              icon: const Icon(Icons.history),
              onPressed: () => showModalBottomSheet(
                  context: context,
                  builder: (_) => ListView(children: [
                        const ListTile(title: Text('Recent changes (this session)')),
                        for (final h in widget.state.history) ListTile(dense: true, title: Text(h)),
                        if (widget.state.history.isEmpty) const ListTile(title: Text('None yet')),
                      ]))),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The scanner (keyboard wedge) types into this field and presses Enter.
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            keyboardType: _softKeyboard ? TextInputType.text : TextInputType.none,
            textInputAction: TextInputAction.search,
            onSubmitted: _scan,
            decoration: InputDecoration(
              labelText: 'Scan barcode or search item name',
              helperText: 'Tap the keyboard icon to type a name',
              border: const OutlineInputBorder(),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: () => _scan(_ctrl.text),
                ),
                IconButton(
                  tooltip: 'Type manually',
                  icon: Icon(_softKeyboard ? Icons.keyboard_hide : Icons.keyboard),
                  onPressed: () {
                    setState(() => _softKeyboard = !_softKeyboard);
                    _focus.unfocus();
                    _focus.requestFocus();
                  },
                ),
              ]),
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16)),
            ),
          if (_hits.isNotEmpty)
            Expanded(
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${_hits.length} items found, tap one:', style: Theme.of(context).textTheme.labelLarge),
                ),
                for (final h in _hits)
                  Card(
                    child: ListTile(
                      title: Text(h.name),
                      subtitle: Text([
                        if (h.reference != null) h.reference!,
                        if (h.barcode != null) h.barcode!,
                      ].join(' · ')),
                      trailing: Text('${fmtQty(h.onHand)} ${h.uom}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => _openHit(h),
                    ),
                  ),
              ]),
            ),
          if (it != null) ...[
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(it.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _row('UOM', it.uom),
                  _row('Barcode', it.itemBarcode ?? '-'),
                  if (it.packaging != null)
                    _row('Scanned pack', '${it.packaging!.name} (${fmtQty(it.packaging!.qty)} ${it.uom})'),
                  _row('Rack location', it.rackLocation ?? '-'),
                  const Divider(height: 28),
                  Text('On hand in ${wh.name}', style: Theme.of(context).textTheme.labelLarge),
                  Text('${fmtQty(it.onHand)} ${it.uom}',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Available: ${fmtQty(it.available)} ${it.uom}'),
                  if (!widget.state.canAdjust)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Your Odoo user is not allowed to update stock.'),
                    ),
                  if (it.tracked)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Lot/serial tracked item: quantity update not supported.'),
                    ),
                ]),
              ),
            ),
            FilledButton.icon(
              onPressed: (it.tracked || !widget.state.canAdjust) ? null : _adjust,
              icon: const Icon(Icons.edit),
              label: const Padding(padding: EdgeInsets.all(12), child: Text('Update quantity')),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 16))),
        ]),
      );
}
