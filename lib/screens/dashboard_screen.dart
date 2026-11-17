import 'package:flutter/material.dart';
import '../app_state.dart';
import '../odoo/models.dart';
import 'scan_screen.dart' show fmtQty;

/// Fast-moving items and average consumption, to help plan purchase requests.
class DashboardScreen extends StatefulWidget {
  final AppState state;
  const DashboardScreen({super.key, required this.state});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _days = 30;
  bool _byCover = false; // false = fastest moving, true = lowest days of cover
  String _filter = '';
  Future<List<ConsumptionRow>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.state.client.consumption(widget.state.warehouse!, _days));
  }

  Color? _coverColor(double? d) {
    if (d == null) return null;
    if (d < 7) return Colors.red;
    if (d < 21) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Consumption · ${widget.state.warehouse!.name}'), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30 days')),
              ButtonSegment(value: 90, label: Text('90 days')),
              ButtonSegment(value: 365, label: Text('12 months')),
            ],
            selected: {_days},
            onSelectionChanged: (s) {
              _days = s.first;
              _load();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Filter by name', border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Reorder soon'),
              selected: _byCover,
              onSelected: (v) => setState(() => _byCover = v),
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<ConsumptionRow>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('${snap.error}')));
              var rows = snap.data!.where((r) => _filter.isEmpty || r.name.toLowerCase().contains(_filter)).toList();
              if (_byCover) {
                rows.sort((a, b) => (a.coverDays ?? 1e9).compareTo(b.coverDays ?? 1e9));
              }
              if (rows.isEmpty) return const Center(child: Text('No consumption found in this period.'));
              return ListView.separated(
                itemCount: rows.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == rows.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Consumption = items that left the store to customers or production, '
                        'shown in the item\'s own unit. Customer returns are not subtracted. '
                        'Days of cover = stock on hand ÷ average use per day.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  final r = rows[i];
                  final cover = r.coverDays;
                  return ListTile(
                    title: Text(r.name),
                    subtitle: Text('Used ${fmtQty(r.out)} ${r.uom} in $_days days\n'
                        'Avg: ${fmtQty(double.parse(r.perWeek.toStringAsFixed(1)))}/week · '
                        '${fmtQty(double.parse(r.perMonth.toStringAsFixed(1)))}/month · '
                        '${fmtQty(double.parse(r.perYear.toStringAsFixed(0)))}/year'),
                    isThreeLine: true,
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${fmtQty(r.onHand)} in stock', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(cover == null ? '-' : '${cover.round()} days left',
                          style: TextStyle(color: _coverColor(cover), fontWeight: FontWeight.w600)),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
