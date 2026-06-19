import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _profileName = 'Default';
  List<String> _availableProfiles = [];
  int _maxPreworkHr = 130;
  int _maxHr = 180;
  double _weightKg = 70.0;
  bool _autoConnectHr = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile([String? forceProfile]) async {
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
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: \$e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'profiles',
        {
          'max_prework_hr': _maxPreworkHr,
          'max_hr': _maxHr,
          'weight_kg': _weightKg,
          'auto_connect_hr': _autoConnectHr ? 1 : 0,
        },
        where: 'name = ?',
        whereArgs: [_profileName],
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Error saving profile: \$e');
    }
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
            ListTile(
              leading: const Icon(Icons.person, size: 40),
              title: _availableProfiles.isEmpty 
                  ? Text(_profileName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _profileName,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        items: _availableProfiles.map((p) {
                          return DropdownMenuItem(value: p, child: Text(p));
                        }).toList(),
                        onChanged: (val) async {
                          if (val != null) {
                            await DatabaseHelper.instance.setActiveProfileName(val);
                            _loadProfile(val);
                          }
                        },
                      ),
                    ),
              subtitle: const Text('Active Profile'),
            ),
            const Divider(height: 32),
            const Text('Heart Rate Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Max Pre-Work HR (bpm)'),
                Slider(
                  value: _maxPreworkHr.toDouble(),
                  min: 80,
                  max: 180,
                  divisions: 100,
                  label: '$_maxPreworkHr',
                  onChanged: (val) => setState(() => _maxPreworkHr = val.toInt()),
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
                Slider(
                  value: _maxHr.toDouble(),
                  min: 140,
                  max: 220,
                  divisions: 80,
                  label: '$_maxHr',
                  onChanged: (val) => setState(() => _maxHr = val.toInt()),
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
                Slider(
                  value: _weightKg,
                  min: 40,
                  max: 150,
                  divisions: 110,
                  label: _weightKg.toStringAsFixed(1),
                  onChanged: (val) => setState(() => _weightKg = val),
                ),
                Text(_weightKg.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-connect Heart Rate Monitor'),
              value: _autoConnectHr,
              onChanged: (val) => setState(() => _autoConnectHr = val),
            ),
          ],
        ),
      ),
    );
  }
}
