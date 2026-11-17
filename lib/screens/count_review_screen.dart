import 'package:flutter/material.dart';
import '../app_state.dart';
import '../count/count_session.dart';
import 'scan_screen.dart' show fmtQty;

/// Shows the differences of a count and posts them to Odoo, reporting any line that fails.
class CountReviewScreen extends StatefulWidget {
  final AppState state;
  const CountReviewScreen({super.key, required this.state});
  @override
  State<CountReviewScreen> createState() => _CountReviewScreenState();
}

class _CountReviewScreenState extends State<CountReviewScreen> {
  bool _busy = false;
  final Map<int, String> _errors = {};
  int _done = 0, _total = 0;
  String? _summary;

  AppState get st => widget.state;
  CountSession get s => st.count!;

  Future<void> _submit() async {
    final todo = s.withDifference;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post to Odoo?'),
        content: Text('${todo.length} item(s) will be adjusted in ${st.warehouse!.name}. This changes real stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Post')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _errors.clear();
      _done = 0;
      _total = todo.length;
      _summary = null;
    });
    final reason = 'Stock count: ${s.name}';
    for (final l in todo) {
      try {
        // Re-read the current stock so the adjustment is applied against today's quantity.
        final fresh = await st.client.byProductId(l.productId, st.warehouse!);
        await st.client.adjust(item: fresh, wh: st.warehouse!, newQty: l.counted, reason: reason);
        st.addHistory('${l.name}: ${fmtQty(fresh.onHand)} → ${fmtQty(l.counted)} ${l.uom} (count)');
        s.lines.remove(l.productId);
      } catch (e) {
        _errors[l.productId] = '$e';
      }
      if (mounted) setState(() => _done++);
    }
    // Lines with no difference are finished too.
    s.lines.removeWhere((_, l) => l.diff == 0 && !_errors.containsKey(l.productId));
    final failed = _errors.length;
    if (s.lines.isEmpty) {
      st.count = null;
    }
    await st.saveCount();
    if (mounted) {
      setState(() {
        _busy = false;
        _summary = failed == 0
            ? 'Done: ${todo.length} item(s) posted.'
            : '${todo.length - failed} posted, $failed failed (listed below). Fix them or try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = st.count == null;
    final lines = finished ? <CountLine>[] : s.lines.values.toList();
    final diffs = finished ? 0 : s.withDifference.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Review count')),
      body: Column(children: [
        if (_summary != null)
          MaterialBanner(content: Text(_summary!), actions: [
            if (finished) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')) else const SizedBox(),
          ]),
        if (_busy) LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
        Expanded(
          child: ListView.separated(
            itemCount: lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = lines[i];
              final err = _errors[l.productId];
              final d = l.diff;
              return ListTile(
                title: Text(l.name),
                subtitle: Text('System ${fmtQty(l.systemQty)} → Counted ${fmtQty(l.counted)} ${l.uom}'
                    '${err != null ? '\n$err' : ''}'),
                isThreeLine: err != null,
                trailing: Text(d == 0 ? 'OK' : '${d > 0 ? '+' : ''}${fmtQty(d)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: d == 0 ? Colors.green : (err != null ? Colors.red : Colors.orange))),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_busy || finished || diffs == 0 || !st.canAdjust) ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(!st.canAdjust
                    ? 'Your Odoo user is not allowed to update stock'
                    : diffs == 0
                        ? 'No differences to post'
                        : 'Submit $diffs difference(s)'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
