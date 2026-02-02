import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/repositories/trip_repository.dart';
import '../models/trip.dart';

final tripsListProvider =
    FutureProvider.family<List<Trip>, DateTime>((ref, date) async {
  return await TripRepository.getByDate(date);
});
