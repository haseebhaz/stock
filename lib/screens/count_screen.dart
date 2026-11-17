import 'package:flutter/material.dart';
import '../app_state.dart';
import '../count/count_session.dart';
import '../scan_feedback.dart';
import 'camera_scan_screen.dart';
import 'count_review_screen.dart';
import 'scan_screen.dart' show fmtQty;

/// Stock-take: scan items and count them, then review and post all differences together.
class CountScreen extends StatefulWidget {
  final AppState state;
  const CountScreen({super.key, required this.state});
  @override
  State<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends State<CountScreen> {
  final _name = TextEditingController();
  final _scan = TextEditingController();
  final _focus = FocusNode();
  String? _message;
  bool _busy = false;

  AppState get st => widget.state;
  CountSession? get session => st.count;

  Future<void> _start() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    st.count = CountSession(n, st.warehouse!.id, DateTime.now());
    await st.saveCount();
    setState(() {});
  }

  Future<void> _onScan(String code) async {
    code = code.trim();
    _scan.clear();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await st.client.lookup(code, st.warehouse!);
      if (r == null) {
        await ScanFeedback.notFound(st.soundEnabled);
        setState(() => _message = 'Barcode not found: $code');
      } else if (r.tracked) {
        await ScanFeedback.notFound(st.soundEnabled);
        setState(() => _message = '${r.name}: lot/serial items are not supported.');
      } else {
        // A pack barcode counts the whole pack, an item barcode counts 1.
        final line = session!.add(
          productId: r.productId,
          name: r.name,
          uom: r.uom,
          barcode: r.itemBarcode,
          systemQty: r.onHand,
          step: r.packaging?.qty ?? 1,
        );
        await st.saveCount();
        await ScanFeedback.found(st.soundEnabled);
        setState(() => _message = '${line.name}: ${fmtQty(line.counted)} ${line.uom}');
      }
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _focus.requestFocus();
    }
  }

  Future<void> _camera() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CameraScanScreen()));
    if (code != null) await _onScan(code);
  }

  Future<void> _edit(CountLine l) async {
    final c = TextEditingController(text: fmtQty(l.counted));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Counted (${l.uom})'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.'))),
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v >= 0) {
      setState(() => l.counted = v);
      await st.saveCount();
    }
    _focus.requestFocus();
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this count?'),
        content: const Text('Nothing has been posted to Odoo. The scanned list will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true) {
      st.count = null;
      await st.saveCount();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final wrongStore = s != null && s.warehouseId != st.warehouse!.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Stock count' : 'Count: ${s.name}'),
        actions: [if (s != null) IconButton(tooltip: 'Discard count', icon: const Icon(Icons.delete_outline), onPressed: _discard)],
      ),
      body: s == null
          ? _startForm()
          : wrongStore
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('The count "${s.name}" was started in another store.\n'
                          'Switch back to that store to continue, or discard it.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _discard, child: const Text('Discard count')),
                    ]),
                  ),
                )
              : _counting(s),
    );
  }

  Widget _startForm() => ListView(padding: const EdgeInsets.all(20), children: [
        Text('Store: ${st.warehouse!.name}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Scan the items on a shelf or aisle. Each scan adds 1 (or the pack quantity '
            'for a carton barcode). Nothing is posted until you review and submit. '
            'Items you do not scan are left unchanged.'),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Count name (e.g. Aisle 3)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _start, child: const Padding(padding: EdgeInsets.all(12), child: Text('Start count'))),
      ]);

  Widget _counting(CountSession s) {
    final lines = s.lines.values.toList().reversed.toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _scan,
          focusNode: _focus,
          autofocus: true,
          keyboardType: TextInputType.none,
          onSubmitted: _onScan,
          decoration: InputDecoration(
            labelText: 'Scan item',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: const Icon(Icons.photo_camera), tooltip: 'Camera scan', onPressed: _camera),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_message!, style: const TextStyle(fontSize: 16))),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('Scan the first item.'))
              : ListView.separated(
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = lines[i];
                    return ListTile(
                      title: Text(l.name),
                      subtitle: Text('System: ${fmtQty(l.systemQty)} ${l.uom}'),
                      trailing: Text('${fmtQty(l.counted)}', style: Theme.of(context).textTheme.headlineSmall),
                      onTap: () => _edit(l),
                      onLongPress: () async {
                        s.lines.remove(l.productId);
                        await st.saveCount();
                        setState(() {});
                      },
                    );
                  },
                ),
        ),
        Text('${s.lines.length} items · tap a line to edit, long-press to remove',
            style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: s.lines.isEmpty
              ? null
              : () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CountReviewScreen(state: st)));
                  if (mounted) setState(() {});
                  _focus.requestFocus();
                },
          icon: const Icon(Icons.fact_check),
          label: const Padding(padding: EdgeInsets.all(12), child: Text('Review & submit')),
        ),
      ]),
    );
  }
}
