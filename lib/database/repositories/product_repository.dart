import '../database_service.dart';
import '../../models/product.dart';

class ProductRepository {
  /// Get all products
  static Future<List<Product>> getAll() async {
    final results =
        await DatabaseService.query('products', orderBy: 'name ASC');
    return results.map((json) => Product.fromJson(json)).toList();
  }

  /// Get products by category
  static Future<List<Product>> getByCategory(int categoryId) async {
    final results = await DatabaseService.query(
      'products',
      where: 'category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'name ASC',
    );
    return results.map((json) => Product.fromJson(json)).toList();
  }

  /// Get product by ID
  static Future<Product?> getById(int id) async {
    final results = await DatabaseService.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return Product.fromJson(results.first);
  }

  /// Create product
  static Future<int> create(Product product) async {
    try {
      return await DatabaseService.insert('products', product.toJson());
    } catch (e) {
      final error = e.toString();
      if (error.contains('UNIQUE constraint failed') ||
          error.contains('2067')) {
        throw Exception('Product with this name already exists.');
      }
      rethrow;
    }
  }

  /// Update product
  static Future<int> update(Product product) async {
    if (product.id == null)
      throw Exception('Product ID is required for update');

    try {
      return await DatabaseService.update(
        'products',
        product.toJson(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
    } catch (e) {
      final error = e.toString();
      if (error.contains('UNIQUE constraint failed') ||
          error.contains('2067')) {
        throw Exception('Product with this name already exists.');
      }
      rethrow;
    }
  }

  /// Delete product
  static Future<int> delete(int id) async {
    return await DatabaseService.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get recipe (raw materials) for a product
  static Future<List<Map<String, dynamic>>> getRecipe(int productId) async {
    const sql = '''
      SELECT 
        prm.raw_material_id, 
        prm.quantity_ratio,
        rm.name as raw_material_name, 
        rm.unit as raw_material_unit
      FROM product_raw_materials prm
      JOIN raw_materials rm ON prm.raw_material_id = rm.id
      WHERE prm.product_id = ?
    ''';

    return await DatabaseService.rawQuery(sql, [productId]);
  }

  /// Save recipe for a product (full replace)
  static Future<void> saveRecipe(
      int productId, List<Map<String, dynamic>> items) async {
    // 1. Delete existing recipe
    await DatabaseService.delete(
      'product_raw_materials',
      where: 'product_id = ?',
      whereArgs: [productId],
    );

    // 2. Insert new items
    for (final item in items) {
      await DatabaseService.insert('product_raw_materials', {
        'product_id': productId,
        'raw_material_id': item['raw_material_id'],
        'quantity_ratio': item['quantity_ratio'],
      });
    }
  }
}
