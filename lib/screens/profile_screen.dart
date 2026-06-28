import 'dart:async';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/health_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _profileName = 'Default';
  List<String> _availableProfiles = [];
  int _maxPreworkHr = 130;
  int _maxHr = 180;
  double _weightKg = 70.0;
  bool _autoConnectHr = true;
  bool _healthEnabled = false;
  bool _saveHistory = true;
  String? _sex;
  String? _birthDate;
  bool _treadmillEnabled = false;
  double _preset1 = 2.0;
  double _preset2 = 4.0;
  double _preset3 = 6.0;
  String _distanceUnitPref = 'km';

  Future<void> _triggerSync() async {
    final success = await SyncService.instance.signInAndSync();

    if (mounted) {
      String msg = success 
          ? 'Sync completed successfully!' 
          : 'Sync failed: ${SyncService.instance.lastError ?? "Unknown error"}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 5),
        ),
      );
      loadProfile();
    }
  }

  @override
  void initState() {
    super.initState();
    loadProfile();
    SyncService.instance.addListener(_onSyncStatusChanged);
  }

  void _onSyncStatusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSyncStatusChanged);
    super.dispose();
  }

  Future<void> loadProfile([String? forceProfile]) async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      
      // Load available profiles
      final allProfiles = await db.query('profiles', columns: ['name']);
      _availableProfiles = allProfiles.map((p) => p['name'] as String).toList();
      
      // Determine which to load
      _profileName = forceProfile ?? await DatabaseHelper.instance.getActiveProfileName();
      
      final results = await db.query('profiles', where: 'name = ?', whereArgs: [_profileName], limit: 1);

      if (results.isNotEmpty) {
        final profile = results.first;
        setState(() {
          _profileName = profile['name'] as String;
          _maxPreworkHr = profile['max_prework_hr'] as int? ?? 130;
          _maxHr = profile['max_hr'] as int? ?? 180;
          _weightKg = (profile['weight_kg'] as num?)?.toDouble() ?? 70.0;
          _autoConnectHr = (profile['auto_connect_hr'] as int? ?? 1) == 1;
          _healthEnabled = (profile['health_enabled'] as int? ?? 0) == 1;
          _saveHistory = (profile['save_history'] as int? ?? 1) == 1;
          _sex = profile['sex'] as String?;
          _birthDate = profile['birth_date'] as String?;
          _treadmillEnabled = (profile['treadmill_enabled'] as int? ?? 0) == 1;
          _preset1 = (profile['treadmill_preset_1'] as num?)?.toDouble() ?? 2.0;
          _preset2 = (profile['treadmill_preset_2'] as num?)?.toDouble() ?? 4.0;
          _preset3 = (profile['treadmill_preset_3'] as num?)?.toDouble() ?? 6.0;
          _distanceUnitPref = profile['distance_unit_pref'] as String? ?? 'km';
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile({bool showFeedback = true}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'profiles',
        {
          'max_prework_hr': _maxPreworkHr,
          'max_hr': _maxHr,
          'weight_kg': _weightKg,
          'auto_connect_hr': _autoConnectHr ? 1 : 0,
          'health_enabled': _healthEnabled ? 1 : 0,
          'save_history': _saveHistory ? 1 : 0,
          'sex': _sex,
          'birth_date': _birthDate,
          'treadmill_enabled': _treadmillEnabled ? 1 : 0,
          'treadmill_preset_1': _preset1,
          'treadmill_preset_2': _preset2,
          'treadmill_preset_3': _preset3,
          'distance_unit_pref': _distanceUnitPref,
        },
        where: 'name = ?',
        whereArgs: [_profileName],
      );
      
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
      }
      
      // Trigger background sync immediately when profile changes
      SyncService.instance.signInAndSync();
    } catch (e) {
      debugPrint('Error saving profile: $e');
    }
  }

  Future<void> _onHealthToggled(bool value) async {
    if (value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Apple Health Integration'),
          content: const Text(
            'ChronoPulse Active will request permission to save your workouts, heart rate logs, and active energy (calories) to Apple Health.\n\n'
            'We will also request read permission for your Biological Sex and Date of Birth. This allows us to auto-populate your profile and compute accurate heart rate zone-based calorie burn estimations during workouts.\n\n'
            'Note: Apple Health is bound to this device\'s active Apple ID. If you share this device with other profiles, saving workouts may mix data in your Apple Health app.\n\n'
            'Do you want to enable Apple Health for this profile?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        final granted = await HealthService.instance.requestPermissions();
        setState(() {
          _healthEnabled = granted;
        });
        if (granted) {
          final characteristics = await HealthService.instance.getCharacteristics();
          setState(() {
            if (characteristics['sex'] != null) {
              _sex = characteristics['sex'];
            }
            if (characteristics['birth_date'] != null) {
              _birthDate = characteristics['birth_date'];
            }
            if (characteristics['weight'] != null) {
              final parsedWeight = double.tryParse(characteristics['weight']!);
              if (parsedWeight != null) {
                _weightKg = parsedWeight.clamp(40.0, 150.0);
              }
            }
          });
        }
        await _saveProfile(showFeedback: false);
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Apple Health permissions denied or not configured.')),
          );
        }
      }
    } else {
      setState(() {
        _healthEnabled = false;
      });
      await _saveProfile(showFeedback: false);
    }
  }

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate != null ? DateTime.parse(_birthDate!) : DateTime(1990, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked.toIso8601String().substring(0, 10);
      });
      await _saveProfile(showFeedback: false);
    }
  }

  Future<void> _onProfileChanged(String val) async {
    await DatabaseHelper.instance.setActiveProfileName(val);
    await loadProfile(val);
  }

  Widget _buildProfileSelectorAction() {
    if (_availableProfiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Chip(
          avatar: Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.primary),
          label: Text(_profileName, style: const TextStyle(fontSize: 12)),
          padding: EdgeInsets.zero,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: PopupMenuButton<String>(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _profileName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: Colors.white,
              ),
            ],
          ),
        ),
        onSelected: (val) async {
          await _onProfileChanged(val);
        },
        itemBuilder: (context) {
          return _availableProfiles.map((p) {
            return PopupMenuItem<String>(
              value: p,
              child: Text(p),
            );
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Management'),
        actions: [
          _buildProfileSelectorAction(),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveProfile,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Heart Rate Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
             Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Max Pre-Work HR (bpm)'),
                Expanded(
                  child: Slider(
                    value: _maxPreworkHr.toDouble(),
                    min: 80,
                    max: 180,
                    divisions: 100,
                    label: '$_maxPreworkHr',
                    onChanged: (val) => setState(() => _maxPreworkHr = val.toInt()),
                    onChangeEnd: (val) => _saveProfile(showFeedback: false),
                  ),
                ),
                Text('$_maxPreworkHr', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Used by Auto Regulation to hold the Rest phase until your HR drops below this value.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Absolute Max HR (bpm)'),
                Expanded(
                  child: Slider(
                    value: _maxHr.toDouble(),
                    min: 140,
                    max: 220,
                    divisions: 80,
                    label: '$_maxHr',
                    onChanged: (val) => setState(() => _maxHr = val.toInt()),
                    onChangeEnd: (val) => _saveProfile(showFeedback: false),
                  ),
                ),
                Text('$_maxHr', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 32),
            const Text('General', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
             Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Weight (kg)'),
                Expanded(
                  child: Slider(
                    value: _weightKg,
                    min: 40,
                    max: 150,
                    divisions: 110,
                    label: _weightKg.toStringAsFixed(1),
                    onChanged: (val) => setState(() => _weightKg = val),
                    onChangeEnd: (val) => _saveProfile(showFeedback: false),
                  ),
                ),
                Text(_weightKg.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birth Date'),
              subtitle: Text(_birthDate ?? 'Not set (defaults to age 35 for calories)'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectBirthDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sex'),
              trailing: DropdownButton<String>(
                value: _sex,
                hint: const Text('Select (defaults to Male for calories)'),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: (val) async {
                  setState(() {
                    _sex = val;
                  });
                  await _saveProfile(showFeedback: false);
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Units of Measurement'),
              subtitle: const Text('Select distance and speed units (Kilometers vs Miles).'),
              trailing: DropdownButton<String>(
                value: _distanceUnitPref,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'km', child: Text('Metric (km, km/h)')),
                  DropdownMenuItem(value: 'mi', child: Text('Imperial (mi, mph)')),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    setState(() {
                      _distanceUnitPref = val;
                    });
                    await _saveProfile(showFeedback: false);
                  }
                },
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-connect Heart Rate Monitor'),
              value: _autoConnectHr,
              onChanged: (val) async {
                setState(() => _autoConnectHr = val);
                await _saveProfile(showFeedback: false);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save Workout History'),
              subtitle: const Text('Automatically record completed sessions and heart rate details.'),
              value: _saveHistory,
              onChanged: (val) async {
                setState(() => _saveHistory = val);
                await _saveProfile(showFeedback: false);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Connect Apple Health'),
              subtitle: const Text('Saves workouts/active energy. Reads sex, birth date, and weight to calculate target heart rate zones and calorie burn.'),
              value: _healthEnabled,
              onChanged: _onHealthToggled,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('WalkingPad Integration'),
              subtitle: const Text('Enable KingSmith R1S WalkingPad treadmill integration and automatic speed control.'),
              value: _treadmillEnabled,
              onChanged: (val) async {
                setState(() {
                  _treadmillEnabled = val;
                });
                await _saveProfile(showFeedback: false);
              },
            ),
            if (_treadmillEnabled) ...[
              const SizedBox(height: 16),
              const Text('Treadmill Speed Presets', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildPresetField('Preset 1', _preset1, (val) => setState(() => _preset1 = val))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildPresetField('Preset 2', _preset2, (val) => setState(() => _preset2 = val))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildPresetField('Preset 3', _preset3, (val) => setState(() => _preset3 = val))),
                ],
              ),
            ],
            const SizedBox(height: 32),
            const Text('Cloud Sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cloud Sync'),
              subtitle: Text(
                SyncService.instance.isSyncing 
                    ? 'Status: ${SyncService.instance.syncStatus}' 
                    : 'Profiles, templates, and history are synced to the cloud.',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: SyncService.instance.isSyncing 
                  ? const SizedBox(
                      width: 24, 
                      height: 24, 
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync Now'),
                      onPressed: _triggerSync,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetField(String label, double valueKmh, ValueChanged<double> onChanged) {
    final bool isMetric = _distanceUnitPref == 'km';
    final double displayVal = isMetric 
        ? double.parse(valueKmh.toStringAsFixed(1))
        : double.parse((valueKmh * 0.621371).toStringAsFixed(1));

    final double step = 0.1;
    final double minVal = isMetric ? 0.5 : 0.3;
    final double maxVal = isMetric ? 10.0 : 6.2;
    final int divisions = ((maxVal - minVal) / step).round();
    final List<double> options = List.generate(divisions + 1, (index) => double.parse((minVal + index * step).toStringAsFixed(1)));

    // Ensure displayVal is in options to avoid DropdownButton assertion error
    if (!options.contains(displayVal)) {
      options.add(displayVal);
      options.sort();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        DropdownButton<double>(
          value: displayVal,
          isExpanded: true,
          underline: Container(
            height: 1,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          items: options
              .map((val) => DropdownMenuItem<double>(
                    value: val,
                    child: Text('${val.toStringAsFixed(1)} ${isMetric ? "km/h" : "mph"}', style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (val) async {
            if (val != null) {
              final double newKmh = isMetric ? val : val * 1.60934;
              onChanged(double.parse(newKmh.toStringAsFixed(1)));
              await _saveProfile(showFeedback: false);
            }
          },
        ),
      ],
    );
  }
}
