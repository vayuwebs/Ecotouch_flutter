class ProductionRawMaterial {
  final int productionId;
  final int rawMaterialId;
  final double quantityUsed;
  final double? bagSize;
  final int? inwardEntryId;
  final int? bagCountUsed;

  // For display purposes (not stored in DB)
  final String? rawMaterialName;

  ProductionRawMaterial({
    required this.productionId,
    required this.rawMaterialId,
    required this.quantityUsed,
    this.bagSize,
    this.inwardEntryId,
    this.bagCountUsed,
    this.rawMaterialName,
  });

  Map<String, dynamic> toJson() {
    return {
      'production_id': productionId,
      'raw_material_id': rawMaterialId,
      'quantity_used': quantityUsed,
      'bag_size': bagSize,
      'inward_entry_id': inwardEntryId,
      'bag_count_used': bagCountUsed,
    };
  }

  factory ProductionRawMaterial.fromJson(Map<String, dynamic> json) {
    return ProductionRawMaterial(
      productionId: json['production_id'] as int,
      rawMaterialId: json['raw_material_id'] as int,
      quantityUsed: (json['quantity_used'] as num).toDouble(),
      bagSize: (json['bag_size'] as num?)?.toDouble(),
      inwardEntryId: json['inward_entry_id'] as int?,
      bagCountUsed: json['bag_count_used'] as int?,
      rawMaterialName: json['raw_material_name'] as String?,
    );
  }
}
