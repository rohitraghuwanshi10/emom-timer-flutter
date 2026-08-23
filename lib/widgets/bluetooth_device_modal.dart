import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/bluetooth_service.dart';
import '../services/treadmill_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../utils/format_utils.dart';

class BluetoothDeviceManagerSheet extends StatefulWidget {
  const BluetoothDeviceManagerSheet({super.key});

  @override
  State<BluetoothDeviceManagerSheet> createState() => _BluetoothDeviceManagerSheetState();
}

class _BluetoothDeviceManagerSheetState extends State<BluetoothDeviceManagerSheet> {
  StreamSubscription? _hrStateSub;
  StreamSubscription? _hrValueSub;
  StreamSubscription? _treadmillStateSub;
  StreamSubscription? _treadmillStatusSub;
  StreamSubscription? _treadmillScanSub;
  StreamSubscription? _hrScanSub;

  BluetoothConnectionState _hrState = BluetoothConnectionState.disconnected;
  int _hrValue = 0;
  BluetoothConnectionState _treadmillState = BluetoothConnectionState.disconnected;
  TreadmillStatus? _treadmillStatus;
  bool _isTreadmillScanning = false;
  bool _isHrScanning = false;
  String _distanceUnitPref = 'km';

  Future<void> _loadDistanceUnitPref() async {
    try {
      final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
      final db = await DatabaseHelper.instance.database;
      final profRes = await db.query('profiles', where: 'name = ?', whereArgs: [activeProfile], limit: 1);
      if (profRes.isNotEmpty && mounted) {
        setState(() {
          _distanceUnitPref = profRes.first['distance_unit_pref'] as String? ?? 'km';
        });
      }
    } catch (e) {
      debugPrint('Error loading distance unit in Bluetooth sheet: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDistanceUnitPref();
    _hrState = AppBluetoothService.instance.isConnected ? BluetoothConnectionState.connected : BluetoothConnectionState.disconnected;
    _treadmillState = TreadmillBluetoothService.instance.connectionState;
    _treadmillStatus = TreadmillBluetoothService.instance.lastStatus;
    _isTreadmillScanning = TreadmillBluetoothService.instance.isScanning;

    _hrStateSub = AppBluetoothService.instance.deviceStateStream.listen((state) {
      if (mounted) setState(() => _hrState = state);
    });
    _hrValueSub = AppBluetoothService.instance.heartRateStream.listen((hr) {
      if (mounted) setState(() => _hrValue = hr);
    });

    _treadmillStateSub = TreadmillBluetoothService.instance.connectionStateStream.listen((state) {
      if (mounted) setState(() => _treadmillState = state);
    });
    _treadmillStatusSub = TreadmillBluetoothService.instance.statusStream.listen((status) {
      if (mounted) setState(() => _treadmillStatus = status);
    });
    _treadmillScanSub = TreadmillBluetoothService.instance.scanningStream.listen((scanning) {
      if (mounted) setState(() => _isTreadmillScanning = scanning);
    });

    _hrScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isHrScanning = scanning);
    });
  }

  @override
  void dispose() {
    _hrStateSub?.cancel();
    _hrValueSub?.cancel();
    _treadmillStateSub?.cancel();
    _treadmillStatusSub?.cancel();
    _treadmillScanSub?.cancel();
    _hrScanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hrConnected = _hrState == BluetoothConnectionState.connected;
    final tmConnected = _treadmillState == BluetoothConnectionState.connected;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Device Connection Manager',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          
          // Card 1: Heart Rate Monitor
          Card(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: hrConnected 
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        color: hrConnected ? Colors.redAccent : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Heart Rate Monitor',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hrConnected 
                                  ? 'Connected (${_hrValue > 0 ? '$_hrValue BPM' : '-- BPM'})'
                                  : (_isHrScanning ? 'Scanning...' : 'Disconnected'),
                              style: TextStyle(
                                fontSize: 12,
                                color: hrConnected 
                                    ? Theme.of(context).colorScheme.primary 
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hrConnected 
                              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.15)
                              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          foregroundColor: hrConnected 
                              ? Theme.of(context).colorScheme.error 
                              : Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          if (hrConnected) {
                            AppBluetoothService.instance.disconnect();
                          } else {
                            AppBluetoothService.instance.startScanAndConnect();
                          }
                        },
                        child: Text(hrConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (TreadmillBluetoothService.instance.treadmillEnabled) ...[
            const SizedBox(height: 16),

            // Card 2: Kingsmith Treadmill
            Card(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: tmConnected 
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.1),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_run,
                          color: tmConnected ? Theme.of(context).colorScheme.primary : Colors.grey,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'WalkingPad Treadmill',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tmConnected 
                                    ? 'Connected'
                                    : (_isTreadmillScanning ? 'Scanning...' : 'Disconnected'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tmConnected 
                                      ? Theme.of(context).colorScheme.primary 
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tmConnected 
                                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.15)
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            foregroundColor: tmConnected 
                                ? Theme.of(context).colorScheme.error 
                                : Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (tmConnected) {
                              TreadmillBluetoothService.instance.disconnect();
                            } else {
                              TreadmillBluetoothService.instance.startScan();
                            }
                          },
                          child: Text(tmConnected ? 'Disconnect' : 'Connect'),
                        ),
                      ],
                    ),
                    
                    if (tmConnected) ...[
                      const Divider(height: 24),
                      // Telemetry Grid
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Builder(
                            builder: (context) {
                              final bool isMetric = _distanceUnitPref == 'km';
                              final double rawSpeed = _treadmillStatus?.speed ?? 0.0;
                              return _buildStatItem('Speed', FormatUtils.formatSpeed(rawSpeed, isMetric: isMetric));
                            }
                          ),
                          Builder(
                            builder: (context) {
                              final bool isMetric = _distanceUnitPref == 'km';
                              final double rawDist = _treadmillStatus?.distance ?? 0.0;
                              return _buildStatItem('Distance', FormatUtils.formatDistance(rawDist, isMetric: isMetric));
                            }
                          ),
                          _buildStatItem('Time', FormatUtils.formatDuration(_treadmillStatus?.time ?? 0)),
                          _buildStatItem('Steps', '${_treadmillStatus?.steps ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Modes Selection Row (standby = 2, manual = 1, auto = 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildModeChip('Standby', 2),
                          const SizedBox(width: 8),
                          _buildModeChip('Manual', 1),
                          const SizedBox(width: 8),
                          _buildModeChip('Automatic', 0),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Controls Row (Speed up, Speed down, Start, Stop)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filledTonal(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              if (_treadmillStatus != null) {
                                TreadmillBluetoothService.instance.setSpeed(_treadmillStatus!.speed - 0.5);
                              }
                            },
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              final state = _treadmillStatus?.beltState;
                              if (state == 1 || state == 2) {
                                TreadmillBluetoothService.instance.stop();
                              } else {
                                TreadmillBluetoothService.instance.start();
                              }
                            },
                            icon: Icon(
                              (_treadmillStatus?.beltState == 1 || _treadmillStatus?.beltState == 2)
                                  ? Icons.stop
                                  : Icons.play_arrow,
                            ),
                            label: Text(
                              (_treadmillStatus?.beltState == 1 || _treadmillStatus?.beltState == 2)
                                  ? 'Stop Belt'
                                  : 'Start Belt',
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              if (_treadmillStatus != null) {
                                TreadmillBluetoothService.instance.setSpeed(_treadmillStatus!.speed + 0.5);
                              }
                            },
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      Text(
                        'Tap to set speed • Long-press to edit preset',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Presets Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildPresetChip(0),
                          const SizedBox(width: 8),
                          _buildPresetChip(1),
                          const SizedBox(width: 8),
                          _buildPresetChip(2),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editPresetSpeed(int index) async {
    final bool isMetric = _distanceUnitPref == 'km';
    final String speedUnit = isMetric ? 'km/h' : 'mph';

    final double minSpeed = isMetric ? 0.5 : 0.3;
    final double maxSpeed = isMetric ? 10.0 : 6.2;
    final int divSpeed = ((maxSpeed - minSpeed) / 0.1).round();

    final currentSpeed = TreadmillBluetoothService.instance.speedPresets[index];
    final double initialSpeed = isMetric ? currentSpeed : currentSpeed * 0.621371;
    double selectedSpeed = initialSpeed.clamp(minSpeed, maxSpeed);

    final newSpeed = await showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Customize Speed Preset'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Preset #${index + 1}: ${selectedSpeed.toStringAsFixed(1)} $speedUnit',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: selectedSpeed,
                    min: minSpeed,
                    max: maxSpeed,
                    divisions: divSpeed,
                    label: '${selectedSpeed.toStringAsFixed(1)} $speedUnit',
                    onChanged: (val) {
                      setDialogState(() {
                        selectedSpeed = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedSpeed),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newSpeed != null && mounted) {
      final double newKmh = isMetric ? newSpeed : newSpeed * 1.60934;
      setState(() {
        TreadmillBluetoothService.instance.speedPresets[index] = double.parse(newKmh.toStringAsFixed(1));
      });
      // Persist to database active profile
      try {
        final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
        final db = await DatabaseHelper.instance.database;
        await db.update(
          'profiles',
          {
            'treadmill_preset_1': TreadmillBluetoothService.instance.speedPresets[0],
            'treadmill_preset_2': TreadmillBluetoothService.instance.speedPresets[1],
            'treadmill_preset_3': TreadmillBluetoothService.instance.speedPresets[2],
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'name = ?',
          whereArgs: [activeProfile],
        );
        debugPrint("TreadmillService: Custom speed presets persisted to DB");
        SyncService.instance.signInAndSync();
      } catch (e) {
        debugPrint("TreadmillService: Error persisting custom speed presets to DB: $e");
      }
    }
  }

  Widget _buildPresetChip(int index) {
    final speed = TreadmillBluetoothService.instance.speedPresets[index];
    final bool isMetric = _distanceUnitPref == 'km';
    final double displaySpeed = isMetric ? speed : speed * 0.621371;
    final String speedUnit = isMetric ? 'km/h' : 'mph';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => TreadmillBluetoothService.instance.setSpeed(speed),
        onLongPress: () => _editPresetSpeed(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            '${displaySpeed.toStringAsFixed(1)} $speedUnit',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeChip(String label, int mode) {
    final active = _treadmillStatus?.mode == mode;

    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (selected) {
        if (selected) {
          TreadmillBluetoothService.instance.setMode(mode);
        }
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
