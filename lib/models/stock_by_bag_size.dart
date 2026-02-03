class StockByBagSize {
  final int materialId;
  final String materialName;
  final double bagSize;
  final int bagCount;
  final double totalWeight;
  final String unit;
  final String containerUnit;
  // Strict Inventory Extensions
  final int? inwardEntryId;
  final DateTime? inwardDate;

  StockByBagSize({
    required this.materialId,
    required this.materialName,
    required this.bagSize,
    required this.bagCount,
    required this.totalWeight,
    required this.unit,
    this.containerUnit = 'units',
    this.inwardEntryId,
    this.inwardDate,
  });

  @override
  String toString() {
    final batchInfo = inwardEntryId != null ? ' (Batch #$inwardEntryId)' : '';
    return '$bagCount packs ($bagSize $unit)$batchInfo = $totalWeight $unit total';
  }
}
