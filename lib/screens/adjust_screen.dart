import 'package:flutter/material.dart';
import '../app_state.dart';
import '../config.dart';
import '../odoo/models.dart';
import 'scan_screen.dart' show fmtQty;

class AdjustScreen extends StatefulWidget {
  final AppState state;
  final StockResult item;
  final Warehouse wh;
  const AdjustScreen({super.key, required this.state, required this.item, required this.wh});
  @override
  State<AdjustScreen> createState() => _AdjustScreenState();
}

class _AdjustScreenState extends State<AdjustScreen> {
  final _qty = TextEditingController();
  String _reason = kAdjustReasons.first;
  bool _inPacks = false;
  bool _busy = false;
  String? _error;

  StockResult get it => widget.item;

  /// New total in base units, or null if the input is not a valid number.
  double? get _newTotal {
    final v = double.tryParse(_qty.text.replaceAll(',', '.'));
    if (v == null || v < 0) return null;
    return _inPacks && it.packaging != null ? v * it.packaging!.qty : v;
  }

  Future<void> _save() async {
    final n = _newTotal;
    if (n == null) {
      setState(() => _error = 'Enter a valid quantity.');
      return;
    }
    final diff = n - it.onHand;
    if (diff == 0) {
      setState(() => _error = 'Quantity is unchanged.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm change'),
        content: Text('${it.name}\nStore: ${widget.wh.name}\n\n'
            'Old: ${fmtQty(it.onHand)} ${it.uom}\n'
            'New: ${fmtQty(n)} ${it.uom}\n'
            'Difference: ${diff > 0 ? '+' : ''}${fmtQty(diff)} ${it.uom}\n'
            'Reason: $_reason'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.client.adjust(item: it, wh: widget.wh, newQty: n, reason: _reason);
      widget.state.addHistory(
          '${it.name}: ${fmtQty(it.onHand)} → ${fmtQty(n)} ${it.uom} ($_reason)');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = it.packaging;
    return Scaffold(
      appBar: AppBar(title: const Text('Update quantity')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(it.name, style: Theme.of(context).textTheme.titleLarge),
        Text('Store: ${widget.wh.name}'),
        const SizedBox(height: 8),
        Text('Current: ${fmtQty(it.onHand)} ${it.uom}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (p != null)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(it.uom)),
              ButtonSegment(value: true, label: Text('${p.name} (×${fmtQty(p.qty)})')),
            ],
            selected: {_inPacks},
            onSelectionChanged: (s) => setState(() => _inPacks = s.first),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _qty,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Counted quantity (${_inPacks && p != null ? p.name : it.uom})',
            helperText: _inPacks && _newTotal != null ? '= ${fmtQty(_newTotal!)} ${it.uom}' : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _reason,
          decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
          items: kAdjustReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => setState(() => _reason = v!),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Review & save'),
          ),
        ),
      ]),
    );
  }
}
