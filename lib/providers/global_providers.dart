import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_service.dart';
import '../database/repositories/product_repository.dart';
import '../database/repositories/raw_material_repository.dart';
import '../models/product.dart';
import '../models/raw_material.dart';
import '../models/worker.dart';
import '../models/stock_item.dart';
import '../database/repositories/worker_repository.dart';
import '../database/repositories/attendance_repository.dart';
import '../database/repositories/production_repository.dart';
import '../services/stock_calculation_service.dart';

/// Global provider for selected date (affects all tabs)
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Provider for SharedPreferences instance (must be overridden in main)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in main');
});

/// Theme Notifier for handling persistence
class ThemeNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;
  static const _themePrefsKey = 'is_dark_mode';

  ThemeNotifier(this._prefs)
      : super(_prefs.getBool(_themePrefsKey) ??
            false); // Default to Light Mode (false)

  void toggleTheme() {
    state = !state;
    _prefs.setBool(_themePrefsKey, state);
  }

  void setTheme(bool isDark) {
    state = isDark;
    _prefs.setBool(_themePrefsKey, state);
  }
}

/// Global provider for theme mode (true = dark, false = light)
final themeModeProvider = StateNotifierProvider<ThemeNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});

/// Global provider for current database path
final databasePathProvider = StateProvider<String?>((ref) => null);

/// Global provider for database instance
final databaseProvider = Provider<Future<Database>>((ref) async {
  final dbPath = ref.watch(databasePathProvider);
  if (dbPath == null) {
    throw Exception('Database path not set');
  }
  return await DatabaseService.initDatabase(dbPath);
});

/// Provider for recent databases list
final recentDatabasesProvider = StateProvider<List<String>>((ref) => []);

/// Provider for checking if user is authenticated
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);

/// Global provider for products list
final productsProvider = FutureProvider<List<Product>>((ref) async {
  return await ProductRepository.getAll();
});

/// Global provider for raw materials list
final rawMaterialsProvider = FutureProvider<List<RawMaterial>>((ref) async {
  return await RawMaterialRepository.getAll();
});

/// Global provider for vehicles list
final vehiclesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return await DatabaseService.query('vehicles', orderBy: 'name ASC');
});

final workersProvider = FutureProvider<List<Worker>>((ref) async {
  return await WorkerRepository.getByType(WorkerType.labour);
});

final dashboardStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final selectedDate = ref.watch(selectedDateProvider);

  // Get attendance count for selected date
  final attendance = await AttendanceRepository.getByDate(selectedDate);
  final workersPresent = attendance.length;

  // Get production count for selected date
  final dailyProduction = await ProductionRepository.getByDate(selectedDate);
  final batchesProduced =
      dailyProduction.fold(0, (sum, item) => sum + item.batches);

  // Get stock status
  final rawMaterialStock =
      await StockCalculationService.getRawMaterialStockItems(selectedDate);
  final productStock =
      await StockCalculationService.getProductStockItems(selectedDate);

  final lowRawMaterials =
      rawMaterialStock.where((s) => s.status != StockStatus.sufficient).length;
  final lowProducts =
      productStock.where((s) => s.status != StockStatus.sufficient).length;
  final criticalItems = [...rawMaterialStock, ...productStock]
      .where((s) => s.status == StockStatus.critical)
      .length;

  // Get production history (Last 7 Days)
  final productionHistory =
      await ProductionRepository.getDailyProductionStats(7);

  return {
    'workersPresent': workersPresent,
    'batchesProduced': batchesProduced,
    'rawMaterialsLow': lowRawMaterials,
    'productsLow': lowProducts,
    'criticalItems': criticalItems,
    'stockAlerts': [...rawMaterialStock, ...productStock]
        .where((s) => s.status != StockStatus.sufficient)
        .toList(),
    'productionHistory': productionHistory,
  };
});
