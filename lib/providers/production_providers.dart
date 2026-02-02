import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/production.dart';
import '../database/repositories/production_repository.dart';

// Provider for fetching details if needed, or re-use existing
final productionListProvider =
    FutureProvider.family<List<Production>, DateTime>((ref, date) async {
  return await ProductionRepository.getByDate(date);
});
