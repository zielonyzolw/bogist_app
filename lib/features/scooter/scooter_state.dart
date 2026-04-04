/// Holds the latest decoded telemetry values from the scooter.
class ScooterState {
  final int speed;       // km/h
  final int batteryRaw;  // raw byte 8 from frame
  final String lastFrameHex;

  const ScooterState({
    this.speed = 0,
    this.batteryRaw = 0,
    this.lastFrameHex = '',
  });

  ScooterState copyWith({
    int? speed,
    int? batteryRaw,
    String? lastFrameHex,
  }) {
    return ScooterState(
      speed: speed ?? this.speed,
      batteryRaw: batteryRaw ?? this.batteryRaw,
      lastFrameHex: lastFrameHex ?? this.lastFrameHex,
    );
  }
}
