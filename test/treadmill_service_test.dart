import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:emom_timer_flutter/services/treadmill_service.dart';

void main() {
  group('TreadmillBluetoothService Command Tests', () {
    late TreadmillBluetoothService service;
    late List<List<int>> capturedCommands;

    setUp(() {
      service = TreadmillBluetoothService.instance;
      capturedCommands = [];
      service.onWriteCmd = (cmd) {
        capturedCommands.add(cmd);
      };
    });

    tearDown(() {
      service.onWriteCmd = null;
    });

    test('startAndSetSpeed does nothing if disconnected', () async {
      service.setMockConnectionState(BluetoothConnectionState.disconnected);
      await service.startAndSetSpeed(4.0);

      expect(capturedCommands, isEmpty);
    });

    test('startAndSetSpeed sends setSpeed directly without start countdown if belt is already running', () async {
      service.setMockConnectionState(BluetoothConnectionState.connected);
      // Simulate that the belt is already active in manual mode (beltState = 1, mode = 1)
      service.setMockStatus(TreadmillStatus(
        beltState: 1,
        mode: 1,
        speed: 2.0,
        time: 10,
        distance: 0.1,
        steps: 120,
      ));

      await service.startAndSetSpeed(4.5);

      // Verify that a speed command was written immediately, and no mode or start toggle commands were sent
      expect(capturedCommands, isNotEmpty);
      
      // Speed command is [247, 162, 1, speedInt, checksum, 253]
      // Speed value of 4.5 km/h is represented as 45 (0x2D)
      final hasSpeedCmd = capturedCommands.any((cmd) => cmd[2] == 1 && cmd[3] == 45);
      final hasStartCmd = capturedCommands.any((cmd) => cmd[2] == 4); // start is command 4
      final hasModeCmd = capturedCommands.any((cmd) => cmd[2] == 2);  // mode change is command 2

      expect(hasSpeedCmd, isTrue, reason: "Should send speed command");
      expect(hasStartCmd, isFalse, reason: "Should NOT toggle start/stop if already running");
      expect(hasModeCmd, isFalse, reason: "Should NOT send redundant mode change");
    });

    test('startAndSetSpeed triggers mode switch and start countdown if belt is stopped', () async {
      service.setMockConnectionState(BluetoothConnectionState.connected);
      // Simulate that the belt is stopped/standby (beltState = 0, mode = 2)
      service.setMockStatus(TreadmillStatus(
        beltState: 0,
        mode: 2,
        speed: 0.0,
        time: 0,
        distance: 0.0,
        steps: 0,
      ));

      // We run startAndSetSpeed. Note: it has Future.delayed inside, so we can't easily wait for the 3s delay in a non-fake async test
      // but we can check if it immediately sends Mode 1 and Start commands.
      await service.startAndSetSpeed(3.0);

      // Mode switch command is [247, 162, 2, mode, checksum, 253] -> mode = 1 (Manual)
      final hasModeCmd = capturedCommands.any((cmd) => cmd[2] == 2 && cmd[3] == 1);
      // Start command is [247, 162, 4, 1, checksum, 253]
      final hasStartCmd = capturedCommands.any((cmd) => cmd[2] == 4 && cmd[3] == 1);

      expect(hasModeCmd, isTrue, reason: "Should switch to manual mode");
      expect(hasStartCmd, isTrue, reason: "Should send start belt command");
    });
  });

  group('Treadmill Statistics Accumulation Logic', () {
    test('Calculates accumulated distance resiliently across pauses and resets', () {
      double accumulatedDistance = 0.0;
      double lastDistanceSample = -1.0;

      // Mock updates from status stream: 0.0 -> 0.1 -> 0.2 -> Pause -> Reset to 0.0 -> Resume -> 0.1 -> 0.2 -> 0.3
      final sequence = [0.0, 0.1, 0.2, 0.0, 0.0, 0.1, 0.2, 0.3];
      for (var dist in sequence) {
        if (lastDistanceSample < 0) {
          lastDistanceSample = dist;
        } else {
          final diff = dist - lastDistanceSample;
          if (diff > 0) {
            accumulatedDistance += diff;
          }
          lastDistanceSample = dist;
        }
      }

      // Expected calculation:
      // 0.0 -> 0.1 (+0.1) -> 0.2 (+0.1) -> total = 0.2
      // 0.2 -> 0.0 (negative, ignored, last sample becomes 0.0)
      // 0.0 -> 0.0 (0, ignored)
      // 0.0 -> 0.1 (+0.1) -> 0.2 (+0.1) -> 0.3 (+0.1) -> total = 0.5
      expect(accumulatedDistance, closeTo(0.5, 0.0001));
    });

    test('Calculates moving average speed ignoring pauses', () {
      final speedSamples = <double>[];
      final rawSamples = [4.0, 0.0, 6.0, 0.0, 5.0];

      for (var speed in rawSamples) {
        if (speed > 0.0) {
          speedSamples.add(speed);
        }
      }

      final avgSpeed = speedSamples.isNotEmpty
          ? (speedSamples.reduce((a, b) => a + b) / speedSamples.length)
          : 0.0;

      // Expected: (4.0 + 6.0 + 5.0) / 3 = 15.0 / 3 = 5.0 km/h
      expect(avgSpeed, equals(5.0));
      expect(speedSamples.length, equals(3));
    });
  });
}
