import 'dart:convert';

class CountLine {
  final int productId;
  final String name;
  final String uom;
  final String? barcode;
  final double systemQty; // on hand when first scanned
  double counted;
  CountLine(this.productId, this.name, this.uom, this.barcode, this.systemQty, this.counted);

  double get diff => counted - systemQty;

  Map<String, dynamic> toJson() => {
        'p': productId, 'n': name, 'u': uom, 'b': barcode, 's': systemQty, 'c': counted,
      };
  factory CountLine.fromJson(Map<String, dynamic> j) => CountLine(
      j['p'], j['n'], j['u'], j['b'], (j['s'] as num).toDouble(), (j['c'] as num).toDouble());
}

/// A stock count in progress: items scanned and counted, not yet posted to Odoo.
class CountSession {
  final String name;
  final int warehouseId;
  final DateTime started;
  final Map<int, CountLine> lines; // insertion order = scan order

  CountSession(this.name, this.warehouseId, this.started, [Map<int, CountLine>? lines])
      : lines = lines ?? {};

  /// Adds [step] to the item's counted quantity (creates the line on first scan).
  CountLine add({
    required int productId,
    required String name,
    required String uom,
    required String? barcode,
    required double systemQty,
    required double step,
  }) {
    final l = lines.putIfAbsent(
        productId, () => CountLine(productId, name, uom, barcode, systemQty, 0));
    l.counted += step;
    return l;
  }

  List<CountLine> get withDifference => lines.values.where((l) => l.diff != 0).toList();

  String encode() => jsonEncode({
        'name': name,
        'wh': warehouseId,
        'at': started.toIso8601String(),
        'lines': lines.values.map((l) => l.toJson()).toList(),
      });

  static CountSession? decode(String? s) {
    if (s == null) return null;
    try {
      final j = jsonDecode(s);
      final ls = {
        for (final x in (j['lines'] as List)) (x['p'] as int): CountLine.fromJson(x)
      };
      return CountSession(j['name'], j['wh'], DateTime.parse(j['at']), ls);
    } catch (_) {
      return null;
    }
  }
}
