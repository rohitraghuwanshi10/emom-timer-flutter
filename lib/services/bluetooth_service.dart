import 'package:flutter/foundation.dart';
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
    debugPrint("BluetoothService: Requesting stop scan...");
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    debugPrint("BluetoothService: Checking system devices...");
    try {
      // First check if the device is already connected to the system
      List<BluetoothDevice> connectedDevices = await FlutterBluePlus.systemDevices([]);
      debugPrint("BluetoothService: Found ${connectedDevices.length} system devices.");
      for (var device in connectedDevices) {
        debugPrint("BluetoothService: System device: ${device.platformName} / ${device.advName}");
        if (device.advName.contains(targetName) || device.platformName.contains(targetName)) {
          debugPrint("BluetoothService: Found target in system devices! Connecting...");
          await _connectToDevice(device);
          return; // Already found and connected!
        }
      }
    } catch (e) {
      debugPrint("BluetoothService: System devices check failed: $e");
    }

    debugPrint("BluetoothService: Starting active scan...");
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final platformName = r.device.platformName;
        final advName = r.device.advName;
        final serviceUuids = r.advertisementData.serviceUuids;
        
        debugPrint("BluetoothService: Scan result - Device: $platformName / $advName, Services: $serviceUuids");
        
        bool hasHrService = serviceUuids.any((uuid) => uuid.toString().toLowerCase().contains('180d'));
        bool matchesName = advName.contains(targetName) || platformName.contains(targetName);
        
        if (hasHrService || matchesName) {
          debugPrint("BluetoothService: MATCH FOUND in scan: $platformName ($advName). Connecting...");
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          break;
        }
      }
    });

    // Scan indefinitely until found (auto-connect will take over once found)
    try {
      // Filter the scan to only look for Heart Rate service to make it robust and fast
      await FlutterBluePlus.startScan(
        withServices: [Guid("180D")],
        continuousUpdates: true,
      );
      debugPrint("BluetoothService: Scan started successfully with service filter [180D].");
    } catch (e) {
      debugPrint("BluetoothService: startScan failed: $e");
      // If it fails (e.g. bluetooth is currently off, or permissions haven't popped up yet),
      // we listen for it to turn on and then retry
      FlutterBluePlus.adapterState.listen((state) {
        debugPrint("BluetoothService: Adapter state changed to: $state");
        if (state == BluetoothAdapterState.on) {
          debugPrint("BluetoothService: Retrying startScan...");
          FlutterBluePlus.startScan(
            withServices: [Guid("180D")],
            continuousUpdates: true,
          ).catchError((e) {
            debugPrint("BluetoothService: Retry startScan failed: $e");
          });
        }
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    debugPrint("BluetoothService: Connecting to ${device.remoteId}...");
    _connectedDevice = device;
    
    _connectionSubscription = device.connectionState.listen((state) async {
      _deviceStateController.add(state);
      debugPrint("BluetoothService: Connection state: $state");
      
      if (state == BluetoothConnectionState.connected) {
        debugPrint("BluetoothService: Connected! Discovering services...");
        await _discoverAndSubscribe(device);
      } else if (state == BluetoothConnectionState.disconnected) {
        debugPrint("BluetoothService: Disconnected. Will attempt auto-reconnect.");
        _hrSubscription?.cancel();
        // The native OS will automatically attempt to reconnect because we use autoConnect: true
        // However, we can also manually trigger a reconnect if it drops completely
        if (_connectedDevice != null) {
          _connectedDevice!.connect(autoConnect: true, mtu: null);
        }
      }
    });

    // Native autoConnect: true tells iOS/Android to automatically re-establish
    // the connection in the background whenever the device is seen again!
    // We must pass mtu: null because mtu negotiations are incompatible with autoConnect.
    await device.connect(autoConnect: true, mtu: null);
  }

  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    debugPrint("BluetoothService: Discovered ${services.length} services.");
    for (var service in services) {
      // 0x180D is the UUID for Heart Rate Service
      if (service.uuid.toString().toLowerCase().contains('180d')) {
        debugPrint("BluetoothService: Found HR Service!");
        for (var characteristic in service.characteristics) {
          // 0x2A37 is the UUID for Heart Rate Measurement Characteristic
          if (characteristic.uuid.toString().toLowerCase().contains('2a37')) {
            debugPrint("BluetoothService: Found HR Characteristic! Subscribing...");
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
