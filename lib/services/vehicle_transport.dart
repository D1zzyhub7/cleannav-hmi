import '../models/vehicle_state.dart';

abstract class VehicleTransport {
  Stream<VehicleState> get states;
  ConnectionKind get kind;
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
