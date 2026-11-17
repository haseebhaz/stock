import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/models.dart';
import 'adjust_screen.dart';

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
  String? _message;
  bool _busy = false;
  bool _softKeyboard = false;

  Warehouse get wh => widget.state.warehouse!;

  Future<void> _scan(String code) async {
    code = code.trim();
    _ctrl.clear();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await widget.state.client.lookup(code, wh);
      setState(() {
        _item = r;
        if (r == null) _message = 'Barcode not found: $code';
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
    if (changed == true) await _scan(_item!.scannedCode);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    return Scaffold(
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
          PopupMenuButton<String>(
            onSelected: (v) => v == 'store' ? widget.state.changeStore() : widget.state.logout(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'store', child: Text('Change store')),
              PopupMenuItem(value: 'out', child: Text('Log out')),
            ],
          ),
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
              labelText: 'Scan or type barcode',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Type manually',
                icon: Icon(_softKeyboard ? Icons.keyboard_hide : Icons.keyboard),
                onPressed: () {
                  setState(() => _softKeyboard = !_softKeyboard);
                  _focus.unfocus();
                  _focus.requestFocus();
                },
              ),
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16)),
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
                  if (it.tracked)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Lot/serial tracked item: quantity update not supported.'),
                    ),
                ]),
              ),
            ),
            FilledButton.icon(
              onPressed: it.tracked ? null : _adjust,
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
