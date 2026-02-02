import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/repositories/inward_repository.dart';
import '../models/inward.dart';

final inwardListProvider =
    FutureProvider.family<List<Inward>, DateTime>((ref, date) async {
  return await InwardRepository.getByDate(date);
});
