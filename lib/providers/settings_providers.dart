import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unit_conversion.dart';
import '../database/repositories/unit_conversion_repository.dart';

final unitConversionsProvider =
    FutureProvider<List<UnitConversion>>((ref) async {
  return await UnitConversionRepository.getAll();
});
