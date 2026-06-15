import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AppBluetoothService {
  static final AppBluetoothService instance = AppBluetoothService._init();
  AppBluetoothService._init();

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _hrSubscription;

  final _hrController = StreamController<int>.broadcast();
  Stream<int> get heartRateStream => _hrController.stream;

  final _deviceStateController = StreamController<BluetoothConnectionState>.broadcast();
  Stream<BluetoothConnectionState> get deviceStateStream => _deviceStateController.stream;

  Future<void> startScanAndConnect({String targetName = 'Polar H10'}) async {
    // Stop any ongoing scan
    await FlutterBluePlus.stopScan();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.advName.contains(targetName) || r.device.platformName.contains(targetName)) {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _connectedDevice = device;
    
    _connectionSubscription = device.connectionState.listen((state) async {
      _deviceStateController.add(state);
      
      if (state == BluetoothConnectionState.connected) {
        await _discoverAndSubscribe(device);
      } else if (state == BluetoothConnectionState.disconnected) {
        // Handle Auto-reconnect logic here if needed
        _hrSubscription?.cancel();
      }
    });

    await device.connect();
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      // 0x180D is the UUID for Heart Rate Service
      if (service.uuid.toString().toLowerCase().contains('180d')) {
        for (var characteristic in service.characteristics) {
          // 0x2A37 is the UUID for Heart Rate Measurement Characteristic
          if (characteristic.uuid.toString().toLowerCase().contains('2a37')) {
            await characteristic.setNotifyValue(true);
            _hrSubscription = characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                final hr = _parseHeartRate(value);
                if (hr != null) {
                  _hrController.add(hr);
                }
              }
            });
          }
        }
      }
    }
  }

  int? _parseHeartRate(List<int> value) {
    if (value.isEmpty) return null;
    
    // The first byte contains the flags. 
    // If the least significant bit is 0, HR is in the 2nd byte (8-bit format).
    // If it's 1, HR is in the 2nd and 3rd bytes (16-bit format).
    int flags = value[0];
    bool is16Bit = (flags & 0x01) != 0;

    if (is16Bit && value.length >= 3) {
      return value[1] | (value[2] << 8);
    } else if (!is16Bit && value.length >= 2) {
      return value[1];
    }
    return null;
  }

  Future<void> disconnect() async {
    await _hrSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
  }
}
