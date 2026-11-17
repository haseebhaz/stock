class Warehouse {
  final int id;
  final String name;
  final String code;
  final int stockLocationId;
  final int viewLocationId; // parent of all locations in the warehouse
  Warehouse(this.id, this.name, this.code, this.stockLocationId, {this.viewLocationId = 0});
}

class Packaging {
  final int id;
  final String name;
  final double qty; // quantity in the item's base unit
  Packaging(this.id, this.name, this.qty);
}

class StockResult {
  final int productId;
  final String name;
  final String uom;
  final String? itemBarcode;
  final String scannedCode;
  final Packaging? packaging; // set when a packaging barcode was scanned
  final double onHand; // selected warehouse only
  final double available; // free qty in selected warehouse
  final String? rackLocation;
  final bool tracked; // lot/serial tracking, not supported in v1

  StockResult({
    required this.productId,
    required this.name,
    required this.uom,
    required this.itemBarcode,
    required this.scannedCode,
    required this.packaging,
    required this.onHand,
    required this.available,
    required this.rackLocation,
    required this.tracked,
  });
}

/// One row in a search-by-name result list.
class ProductHit {
  final int id;
  final String name;
  final String? barcode;
  final String? reference;
  final String uom;
  final double onHand; // selected warehouse only
  ProductHit(this.id, this.name, this.barcode, this.reference, this.uom, this.onHand);
}

/// What the logged-in Odoo user may do. null = could not be determined.
class AccessRights {
  final bool? canView; // Inventory > User
  final bool? canAdjust; // Inventory > Administrator
  const AccessRights({this.canView, this.canAdjust});
}

/// On-hand quantity of one item in one warehouse.
class StoreStock {
  final String warehouse;
  final double qty;
  StoreStock(this.warehouse, this.qty);
}

/// Consumption of one item over a look-back window (for purchase planning).
class ConsumptionRow {
  final int productId;
  final String name;
  final String uom;
  final double out; // quantity that left the store in the window
  final double onHand;
  final int days; // window length
  ConsumptionRow(this.productId, this.name, this.uom, this.out, this.onHand, this.days);

  double get perDay => out / days;
  double get perWeek => perDay * 7;
  double get perMonth => perDay * 30;
  double get perYear => perDay * 365;

  /// How many days the current stock lasts at the average rate (null = no consumption).
  double? get coverDays => perDay > 0 ? onHand / perDay : null;
}

class OdooException implements Exception {
  final String message;
  OdooException(this.message);
  @override
  String toString() => message;
}
