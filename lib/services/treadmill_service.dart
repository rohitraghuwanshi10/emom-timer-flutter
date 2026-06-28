import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class TreadmillStatus {
  final int beltState; // 0 = standby, 1 = manual/running, 2 = auto, 5 = standby/paused/done
  final int mode; // 0 = Auto, 1 = Manual, 2 = Standby
  final double speed; // in km/h
  final int time; // in seconds
  final double distance; // in km
  final int steps;

  TreadmillStatus({
    required this.beltState,
    required this.mode,
    required this.speed,
    required this.time,
    required this.distance,
    required this.steps,
  });

  @override
  String toString() {
    return 'TreadmillStatus(state: $beltState, mode: $mode, speed: $speed km/h, time: $time s, distance: $distance km, steps: $steps)';
  }
}

class TreadmillBluetoothService {
  static final TreadmillBluetoothService instance = TreadmillBluetoothService._init();
  TreadmillBluetoothService._init();

  bool logVerbose = false;
  bool treadmillEnabled = false;

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  Timer? _pollTimer;

  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  TreadmillStatus? _lastStatus;
  bool _isScanning = false;

  // Custom GATT Service & Characteristics for WalkingPad
  static const String serviceUuid = "0000fe00-0000-1000-8000-00805f9b34fb";
  static const String notifyCharUuid = "0000fe01-0000-1000-8000-00805f9b34fb";
  static const String writeCharUuid = "0000fe02-0000-1000-8000-00805f9b34fb";

  BluetoothCharacteristic? _writeCharacteristic;

  // Stream Controllers
  final _statusController = StreamController<TreadmillStatus>.broadcast();
  final _connectionStateController = StreamController<BluetoothConnectionState>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();

  // Getters
  TreadmillStatus? get lastStatus => _lastStatus;
  bool get isConnected => _connectionState == BluetoothConnectionState.connected;
  BluetoothConnectionState get connectionState => _connectionState;
  Stream<TreadmillStatus> get statusStream => _statusController.stream;
  Stream<BluetoothConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<bool> get scanningStream => _scanningController.stream;
  bool get isScanning => _isScanning;

  // Config States for Auto Speed Sync
  bool autoSpeedSync = false;
  double workSpeed = 4.0;
  double restSpeed = 0.0;
  List<double> speedPresets = [2.0, 4.0, 6.0];

  // For unit testing only: intercept commands before writing to BLE
  @visibleForTesting
  void Function(List<int> cmd)? onWriteCmd;

  @visibleForTesting
  void setMockStatus(TreadmillStatus status) {
    _lastStatus = status;
    _statusController.add(status);
  }
  
  @visibleForTesting
  void setMockConnectionState(BluetoothConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  // Scan for KingSmith/WalkingPad devices
  Future<void> startScan() async {
    if (_isScanning) return;
    
    _isScanning = true;
    _scanningController.add(true);

    debugPrint("TreadmillService: Starting scan...");
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final platformName = r.device.platformName.toLowerCase();
        final advName = r.device.advName.toLowerCase();
        final serviceUuids = r.advertisementData.serviceUuids;

        bool hasTreadmillService = serviceUuids.any((uuid) => uuid.toString().toLowerCase().contains('fe00'));
        bool matchesName = platformName.contains('walkingpad') || 
                            platformName.contains('kingsmith') || 
                            platformName.contains('treadmill') ||
                            advName.contains('walkingpad') || 
                            advName.contains('kingsmith') || 
                            advName.contains('treadmill');

        if (hasTreadmillService || matchesName) {
          debugPrint("TreadmillService: Found treadmill candidate: ${r.device.platformName} (${r.device.advName})");
          stopScan();
          connect(r.device);
          break;
        }
      }
    });

    try {
      // Scan for 15 seconds max
      await FlutterBluePlus.startScan(
        withServices: [Guid(serviceUuid)],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint("TreadmillService: startScan error: $e");
      _isScanning = false;
      _scanningController.add(false);
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    _isScanning = false;
    _scanningController.add(false);
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _scanSubscription?.cancel();
  }

  // Connect to the treadmill device
  Future<void> connect(BluetoothDevice device) async {
    await disconnect();

    _connectedDevice = device;
    _connectionState = BluetoothConnectionState.connecting;
    _connectionStateController.add(_connectionState);

    debugPrint("TreadmillService: Connecting to ${device.platformName}...");

    _connectionSubscription = device.connectionState.listen((state) {
      debugPrint("TreadmillService: Connection state changed to $state");
      if (_connectionState == state) return; // Skip duplicate states
      _connectionState = state;
      _connectionStateController.add(state);

      if (state == BluetoothConnectionState.disconnected) {
        _cleanupConnection();
      } else if (state == BluetoothConnectionState.connected) {
        _setupDevice(device);
      }
    });

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      debugPrint("TreadmillService: device.connect completed successfully.");
      // Explicitly set and notify connected state if not already set, preventing race conditions or stream dropouts on some OS platforms
      if (_connectionState != BluetoothConnectionState.connected) {
        _connectionState = BluetoothConnectionState.connected;
        _connectionStateController.add(_connectionState);
        _setupDevice(device);
      }
    } catch (e) {
      debugPrint("TreadmillService: Connection failed: $e");
      _connectionState = BluetoothConnectionState.disconnected;
      _connectionStateController.add(_connectionState);
      _cleanupConnection();
    }
  }

  // Disconnect from the treadmill device
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    if (_connectedDevice != null) {
      debugPrint("TreadmillService: Disconnecting...");
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
    }
    _cleanupConnection();
  }

  void _cleanupConnection() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _writeCharacteristic = null;
    _connectedDevice = null;
    _lastStatus = null;
    _connectionState = BluetoothConnectionState.disconnected;
    _connectionStateController.add(_connectionState);
  }

  // Discover services and characteristics
  Future<void> _setupDevice(BluetoothDevice device) async {
    try {
      debugPrint("TreadmillService: Discovering services...");
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? notifyChar;

      for (var s in services) {
        if (s.uuid.toString().toLowerCase().contains('fe00')) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toLowerCase().contains('fe01')) {
              notifyChar = c;
            } else if (c.uuid.toString().toLowerCase().contains('fe02')) {
              _writeCharacteristic = c;
            }
          }
        }
      }

      if (notifyChar != null && _writeCharacteristic != null) {
        debugPrint("TreadmillService: Found WalkingPad GATT characteristics.");

        // Subscribe to notifications
        await notifyChar.setNotifyValue(true);
        _notifySubscription = notifyChar.lastValueStream.listen((data) {
          _handleIncomingData(data);
        });

        // Start polling stats every 1 second
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          askStats();
        });

        // Query initial stats
        await askStats();
      } else {
        debugPrint("TreadmillService: Required GATT characteristics not found.");
        disconnect();
      }
    } catch (e) {
      debugPrint("TreadmillService: Setup device error: $e");
      disconnect();
    }
  }

  // Parse WalkingPad incoming data (F8 A2 ...)
  void _handleIncomingData(List<int> data) {
    if (logVerbose) debugPrint("TreadmillService: Received notification data: $data");
    if (data.length < 5 || data[0] != 248 || data[1] != 162) {
      return;
    }

    final beltState = data[2];
    final speed = data[3] / 10.0; // speed raw in units of 0.1 km/h
    final mode = data[4];

    // Read 3-byte telemetry fields dynamically based on length
    final time = data.length >= 8 ? _bytesToInt(data, 5) : 0;
    final distance = data.length >= 11 ? _bytesToInt(data, 8) / 100.0 : 0.0;
    final steps = data.length >= 14 ? _bytesToInt(data, 11) : 0;

    final status = TreadmillStatus(
      beltState: beltState,
      mode: mode,
      speed: speed,
      time: time,
      distance: distance,
      steps: steps,
    );

    _lastStatus = status;
    _statusController.add(status);
  }

  int _bytesToInt(List<int> val, int start) {
    if (start + 3 > val.length) return 0;
    return (val[start] << 16) | (val[start + 1] << 8) | val[start + 2];
  }

  // Checksum calculation (cmd[-2] = sum(cmd[1:-2]) % 256)
  List<int> _fixCrc(List<int> cmd) {
    int sum = 0;
    for (int i = 1; i < cmd.length - 2; i++) {
      sum += cmd[i];
    }
    cmd[cmd.length - 2] = sum % 256;
    return cmd;
  }

  // Write commands to FE02
  Future<void> _sendCmd(List<int> cmd) async {
    final fixedCmd = _fixCrc(List<int>.from(cmd));
    if (onWriteCmd != null) {
      onWriteCmd!(fixedCmd);
    }
    if (_writeCharacteristic == null) return;
    try {
      if (logVerbose) debugPrint("TreadmillService: Writing command: $fixedCmd");
      // WalkingPad FE02 is a write-without-response characteristic.
      // Forcing write-with-response (withoutResponse: false) can fail or hang on some OS Bluetooth stacks.
      await _writeCharacteristic!.write(fixedCmd, withoutResponse: true);
    } catch (e) {
      debugPrint("TreadmillService: Write command error: $e");
      try {
        final fixedCmd = _fixCrc(List<int>.from(cmd));
        await _writeCharacteristic!.write(fixedCmd, withoutResponse: false);
      } catch (e2) {
        debugPrint("TreadmillService: Fallback write command error: $e2");
      }
    }
  }

  // Poll stats: [247, 162, 0, 0, 162, 253] (hex: F7 A2 00 00 A2 FD)
  Future<void> askStats() async {
    await _sendCmd([247, 162, 0, 0, 0, 253]);
  }

  // Start belt: [247, 162, 4, 1, 167, 253] (hex: F7 A2 04 01 A7 FD)
  Future<void> start() async {
    debugPrint("TreadmillService: Sending start command...");
    await _sendCmd([247, 162, 4, 1, 0, 253]);
  }

  // Stop belt: set speed to 0.0
  Future<void> stop() async {
    debugPrint("TreadmillService: Sending stop command...");
    await setSpeed(0.0);
  }

  // Change speed: [247, 162, 1, speedInt, checksum, 253]
  Future<void> setSpeed(double speedKmH) async {
    if (!isConnected) return;
    
    // Lock within limits (e.g. 0.0 to 10.0 km/h)
    double targetSpeed = speedKmH.clamp(0.0, 10.0);
    int speedInt = (targetSpeed * 10).round();

    debugPrint("TreadmillService: Setting speed to $targetSpeed km/h ($speedInt)...");
    await _sendCmd([247, 162, 1, speedInt, 0, 253]);
  }

  // Set mode: [247, 162, 2, mode, checksum, 253]
  // 0 = Auto, 1 = Manual, 2 = Standby
  Future<void> setMode(int mode) async {
    if (!isConnected) return;
    debugPrint("TreadmillService: Switching mode to $mode...");
    if (mode == 2) {
      // Switching to Standby: slow down the belt first so the command is accepted
      await setSpeed(0.0);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await _sendCmd([247, 162, 2, mode, 0, 253]);
  }

  // Starts belt, waits for countdown, then sets target speed
  Future<void> startAndSetSpeed(double speedKmH) async {
    if (!isConnected) return;

    // If the belt is already running, adjust the speed directly without toggling start/stop
    if (_lastStatus != null && _lastStatus!.beltState == 1) {
      debugPrint("TreadmillService: Belt is already running. Adjusting speed directly to $speedKmH...");
      await setSpeed(speedKmH);
      return;
    }

    // Switch to manual mode if not already in manual mode
    if (_lastStatus == null || _lastStatus!.mode != 1) {
      await setMode(1); 
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    // Trigger Start
    await start();

    // Treadmills show a 3-second startup countdown beep before moving. 
    // We delay setting speed until countdown completes.
    Future.delayed(const Duration(seconds: 3), () async {
      if (isConnected && _lastStatus != null && _lastStatus!.beltState == 1) {
        await setSpeed(speedKmH);
      }
    });
  }
}
