import '../models/hil_snapshot.dart';
import '../models/occupancy_map.dart';

abstract class VehicleTransport {
  Stream<HilSnapshot> get snapshots;
  Stream<OccupancyMap?> get maps;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendTask(int taskId, {bool userConfirmed = false});
  Future<void> dispose();
}

class TransportException implements Exception {
  const TransportException(this.message);
  final String message;
  @override
  String toString() => message;
}
