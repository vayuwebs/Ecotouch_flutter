import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/repositories/outward_repository.dart';
import '../models/outward.dart';

final outwardListProvider =
    FutureProvider.family<List<Outward>, DateTime>((ref, date) async {
  return await OutwardRepository.getByDate(date);
});
