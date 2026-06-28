import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import 'package:sqflite/sqflite.dart';

class LibraryScreen extends StatefulWidget {
  final Function(Map<String, dynamic> template) onWorkoutSelected;

  const LibraryScreen({super.key, required this.onWorkoutSelected});

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> {
  String _profileName = 'Default';
  List<String> _availableProfiles = [];
  List<Map<String, dynamic>> _allTemplates = [];
  List<Map<String, dynamic>> _filteredTemplates = [];
  String _searchQuery = '';
  String _selectedActivityFilter = 'All';

  final TextEditingController _searchController = TextEditingController();

  final List<String> _activityTypes = [
    'All',
    'HIIT',
    'STRENGTH',
    'FUNCTIONAL_STRENGTH',
    'CORE',
    'CARDIO',
    'YOGA',
    'PILATES',
    'CALISTHENICS',
    'OTHER',
  ];

  @override
  void initState() {
    super.initState();
    loadTemplates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadTemplates() async {
    try {
      final activeProfile = await DatabaseHelper.instance.getActiveProfileName();
      final db = await DatabaseHelper.instance.database;
      
      final allProfiles = await db.query('profiles', columns: ['name']);
      final profileNames = allProfiles.map((p) => p['name'] as String).toList();
      
      final templates = await db.query(
        'workout_templates',
        where: 'profile_name = ?',
        whereArgs: [activeProfile],
      );
 
      if (mounted) {
        setState(() {
          _profileName = activeProfile;
          _availableProfiles = profileNames;
          _allTemplates = templates;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('LibraryScreen: Error loading templates: $e');
    }
  }

  Future<void> _onProfileChanged(String val) async {
    await DatabaseHelper.instance.setActiveProfileName(val);
    await loadTemplates();
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

  void _applyFilters() {
    List<Map<String, dynamic>> results = _allTemplates;

    if (_searchQuery.isNotEmpty) {
      results = results.where((t) {
        final name = (t['template_name'] as String? ?? '').toLowerCase();
        return name.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedActivityFilter != 'All') {
      results = results.where((t) {
        return (t['activity_type'] as String? ?? 'HIIT') == _selectedActivityFilter;
      }).toList();
    }

    setState(() {
      _filteredTemplates = results;
    });
  }

  String _getActivityName(String code) {
    switch (code) {
      case 'HIIT':
        return 'HIIT / Interval';
      case 'STRENGTH':
        return 'Strength Training';
      case 'FUNCTIONAL_STRENGTH':
        return 'Functional Strength';
      case 'CORE':
        return 'Core Training';
      case 'CARDIO':
        return 'Mixed Cardio';
      case 'YOGA':
        return 'Yoga';
      case 'PILATES':
        return 'Pilates';
      case 'CALISTHENICS':
        return 'Calisthenics';
      default:
        return 'Other';
    }
  }

  Color _getActivityColor(String code) {
    switch (code) {
      case 'HIIT':
        return const Color(0xFFBD93F9); // Neon Purple
      case 'STRENGTH':
        return const Color(0xFF81A1C1); // Steel Blue
      case 'FUNCTIONAL_STRENGTH':
        return const Color(0xFF88C0D0); // Teal
      case 'CORE':
        return const Color(0xFFD08770); // Orange
      case 'CARDIO':
        return const Color(0xFF0DF2A3); // Mint Neon
      case 'YOGA':
        return const Color(0xFFB48EAD); // Lavender
      case 'PILATES':
        return const Color(0xFFFF79C6); // Pink
      case 'CALISTHENICS':
        return const Color(0xFFEBCB8B); // Yellow
      default:
        return const Color(0xFF4C566A); // Gray
    }
  }

  String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return '${hours}h ${minutes}m';
    }
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins == 0) return '${secs}s';
    if (secs == 0) return '${mins}m';
    return '${mins}m ${secs}s';
  }

  double _secondsToSliderValue(int seconds) {
    if (seconds <= 300) {
      final pct = (seconds - 10) / (300 - 10);
      return pct * 0.5;
    } else {
      final pct = (seconds - 300) / (3600 - 300);
      return 0.5 + pct * 0.5;
    }
  }

  int _sliderValueToSeconds(double value) {
    if (value <= 0.5) {
      final pct = value / 0.5;
      final seconds = 10 + (300 - 10) * pct;
      return ((seconds / 5).round() * 5).clamp(10, 300);
    } else {
      final pct = (value - 0.5) / 0.5;
      final seconds = 300 + (3600 - 300) * pct;
      return ((seconds / 60).round() * 60).clamp(300, 3600);
    }
  }

  int _decrementWorkDuration(int current) {
    if (current <= 10) return 10;
    if (current <= 300) {
      return (current - 5).clamp(10, 3600);
    } else {
      final newDuration = ((current - 60) / 60).floor() * 60;
      return newDuration.clamp(300, 3600);
    }
  }

  int _incrementWorkDuration(int current) {
    if (current >= 3600) return 3600;
    if (current < 300) {
      return (current + 5).clamp(10, 3600);
    } else {
      final newDuration = ((current + 60) / 60).floor() * 60;
      return newDuration.clamp(300, 3600);
    }
  }

  double _secondsToRestSliderValue(int seconds) {
    if (seconds <= 120) {
      final pct = seconds / 120.0;
      return pct * 0.5;
    } else {
      final pct = (seconds - 120) / (900.0 - 120.0);
      return 0.5 + pct * 0.5;
    }
  }

  int _sliderValueToRestSeconds(double value) {
    if (value <= 0.5) {
      final pct = value / 0.5;
      final seconds = 120.0 * pct;
      return ((seconds / 5).round() * 5).clamp(0, 120);
    } else {
      final pct = (value - 0.5) / 0.5;
      final seconds = 120.0 + (900.0 - 120.0) * pct;
      return ((seconds / 30).round() * 30).clamp(120, 900);
    }
  }

  int _decrementRestDuration(int current) {
    if (current <= 0) return 0;
    if (current <= 120) {
      return (current - 5).clamp(0, 900);
    } else {
      final newDuration = ((current - 30) / 30).floor() * 30;
      return newDuration.clamp(120, 900);
    }
  }

  int _incrementRestDuration(int current) {
    if (current >= 900) return 900;
    if (current < 120) {
      return (current + 5).clamp(0, 900);
    } else {
      final newDuration = ((current + 30) / 30).floor() * 30;
      return newDuration.clamp(120, 900);
    }
  }



  Future<void> _deleteTemplate(Map<String, dynamic> template) async {
    final name = template['template_name'] as String;
    final id = template['id'] as int;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workout?'),
        content: Text('Are you sure you want to delete "$name" from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final db = await DatabaseHelper.instance.database;
        await db.delete('workout_templates', where: 'id = ?', whereArgs: [id]);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" deleted from library')),
        );
        
        await loadTemplates();
        
        // Delete from Firestore
        await SyncService.instance.deleteTemplateRemote(_profileName, name);
      } catch (e) {
        debugPrint('LibraryScreen: Error deleting template: $e');
      }
    }
  }

  void _showWorkoutEditor({Map<String, dynamic>? template}) {
    final isEditing = template != null;
    final nameController = TextEditingController(text: isEditing ? template['template_name'] as String : '');
    final notesController = TextEditingController(text: isEditing ? template['notes'] as String? ?? '' : '');
    
    int rounds = isEditing ? template['rounds'] as int : 10;
    int workTime = isEditing ? template['work_time'] as int : 60;
    int restTime = isEditing ? template['rest_time'] as int : 10;
    bool continuous = isEditing ? (template['continuous_mode'] as int? ?? 0) == 1 : false;
    String activityType = isEditing ? template['activity_type'] as String? ?? 'HIIT' : 'HIIT';
    bool autoRegulate = isEditing ? (template['auto_regulate'] as int? ?? 1) == 1 : true;
    bool treadmillWorkout = isEditing ? (template['treadmill_workout'] as int? ?? 0) == 1 : false;
    double workSpeed = isEditing ? (template['work_speed'] as num?)?.toDouble() ?? 4.0 : 4.0;
    double restSpeed = isEditing ? (template['rest_speed'] as num?)?.toDouble() ?? 0.0 : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEditing ? 'Edit Workout Template' : 'New Workout Template',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Workout Name',
                        hintText: 'e.g. Kettlebell Armor Building',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 40,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: activityType,
                      decoration: const InputDecoration(
                        labelText: 'Activity Type',
                        border: OutlineInputBorder(),
                      ),
                      items: _activityTypes
                          .where((t) => t != 'All')
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(_getActivityName(type)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            activityType = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    // Rounds Slider & Steppers
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Rounds', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('$rounds', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                setModalState(() {
                                  rounds = (rounds - 1).clamp(1, 100);
                                });
                              },
                            ),
                            Expanded(
                              child: Slider(
                                value: rounds.toDouble(),
                                min: 1,
                                max: 100,
                                divisions: 99,
                                onChanged: (val) {
                                  setModalState(() {
                                    rounds = val.toInt();
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                setModalState(() {
                                  rounds = (rounds + 1).clamp(1, 100);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Work Slider & Steppers
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Work Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(_formatDuration(workTime), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                setModalState(() {
                                  workTime = _decrementWorkDuration(workTime);
                                });
                              },
                            ),
                            Expanded(
                              child: Slider(
                                value: _secondsToSliderValue(workTime),
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) {
                                  setModalState(() {
                                    workTime = _sliderValueToSeconds(val);
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                setModalState(() {
                                  workTime = _incrementWorkDuration(workTime);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Rest Slider & Steppers
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Rest Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(restTime == 0 ? 'None' : _formatDuration(restTime), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                setModalState(() {
                                  restTime = _decrementRestDuration(restTime);
                                });
                              },
                            ),
                            Expanded(
                              child: Slider(
                                value: _secondsToRestSliderValue(restTime),
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) {
                                  setModalState(() {
                                    restTime = _sliderValueToRestSeconds(val);
                                  });
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                setModalState(() {
                                  restTime = _incrementRestDuration(restTime);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Continuous Mode
                    SwitchListTile(
                      title: const Text('Open Ended'),
                      subtitle: const Text('Timer runs until you tap stop'),
                      value: continuous,
                      onChanged: (val) {
                        setModalState(() {
                          continuous = val;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    // Auto Regulate Rest
                    SwitchListTile(
                      title: const Text('Auto Regulate Rest'),
                      subtitle: const Text('Delay rounds based on heart rate threshold'),
                      value: autoRegulate,
                      onChanged: (val) {
                        setModalState(() {
                          autoRegulate = val;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    // Treadmill Workout Checkbox/Switch
                    SwitchListTile(
                      title: const Text('Treadmill Workout'),
                      subtitle: const Text('Check this if the workout is treadmill related'),
                      value: treadmillWorkout,
                      onChanged: (val) {
                        setModalState(() {
                          treadmillWorkout = val;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (treadmillWorkout) ...[
                      const SizedBox(height: 8),
                      // Work Speed Slider for Template
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Treadmill Work Speed', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('${workSpeed.toStringAsFixed(1)} km/h',
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: workSpeed,
                        min: 0.5,
                        max: 10.0,
                        divisions: 95,
                        label: '${workSpeed.toStringAsFixed(1)} km/h',
                        onChanged: (val) {
                          setModalState(() {
                            workSpeed = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      // Rest Speed Slider for Template
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Treadmill Rest Speed', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(restSpeed == 0.0 ? 'Stop (0.0 km/h)' : '${restSpeed.toStringAsFixed(1)} km/h',
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: restSpeed,
                        min: 0.0,
                        max: 10.0,
                        divisions: 100,
                        label: restSpeed == 0.0 ? 'Stop' : '${restSpeed.toStringAsFixed(1)} km/h',
                        onChanged: (val) {
                          setModalState(() {
                            restSpeed = val;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Target Weight & Exercise Notes',
                        hintText: 'e.g. Double 20kg Kettlebells',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a workout name')),
                          );
                          return;
                        }

                        try {
                          final db = await DatabaseHelper.instance.database;
                          
                          if (isEditing) {
                            // Update template in DB
                            await db.update(
                              'workout_templates',
                              {
                                'template_name': name,
                                'rounds': rounds,
                                'work_time': workTime,
                                'rest_time': restTime,
                                'notes': notesController.text,
                                'continuous_mode': continuous ? 1 : 0,
                                'activity_type': activityType,
                                'auto_regulate': autoRegulate ? 1 : 0,
                                'treadmill_workout': treadmillWorkout ? 1 : 0,
                                'work_speed': workSpeed,
                                'rest_speed': restSpeed,
                              },
                              where: 'id = ?',
                              whereArgs: [template['id']],
                            );
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Workout updated')),
                            );
                          } else {
                            // Insert new template
                            await db.insert(
                              'workout_templates',
                              {
                                'profile_name': _profileName,
                                'template_name': name,
                                'rounds': rounds,
                                'work_time': workTime,
                                'rest_time': restTime,
                                'notes': notesController.text,
                                'continuous_mode': continuous ? 1 : 0,
                                'activity_type': activityType,
                                'auto_regulate': autoRegulate ? 1 : 0,
                                'treadmill_workout': treadmillWorkout ? 1 : 0,
                                'work_speed': workSpeed,
                                'rest_speed': restSpeed,
                              },
                              conflictAlgorithm: ConflictAlgorithm.replace,
                            );
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Workout added to library')),
                            );
                          }
                          
                          if (context.mounted) Navigator.pop(context);
                          loadTemplates();
                          
                          // Trigger sync in background
                          SyncService.instance.signInAndSync();
                        } catch (e) {
                          debugPrint('Error saving template: $e');
                        }
                      },
                      child: Text(isEditing ? 'Save Changes' : 'Create Workout'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Library'),
        actions: [
          _buildProfileSelectorAction(),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing library...')),
              );
              await SyncService.instance.signInAndSync();
              loadTemplates();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showWorkoutEditor(),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Search & Filter Panel
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                      _applyFilters();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search workouts...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _applyFilters();
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 10),
                // Horizontal category filter pills
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _activityTypes.length,
                    itemBuilder: (context, index) {
                      final type = _activityTypes[index];
                      final isSelected = _selectedActivityFilter == type;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(type == 'All' ? 'All Types' : _getActivityName(type)),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _selectedActivityFilter = type;
                                _applyFilters();
                              });
                            }
                          },
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          selectedColor: Theme.of(context).colorScheme.primary,
                          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Workout Cards List
          Expanded(
            child: _filteredTemplates.isEmpty
                ? Center(
                    child: Text(
                      _allTemplates.isEmpty
                          ? 'Your workout library is empty.\nTap the + button to create a workout!'
                          : 'No workouts match your filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredTemplates.length,
                    itemBuilder: (context, index) {
                      final t = _filteredTemplates[index];
                      final name = t['template_name'] as String;
                      final type = t['activity_type'] as String? ?? 'HIIT';
                      final rounds = t['rounds'] as int;
                      final work = t['work_time'] as int;
                      final rest = t['rest_time'] as int;
                      final notes = t['notes'] as String? ?? '';
                      final continuous = (t['continuous_mode'] as int? ?? 0) == 1;

                      final badgeColor = _getActivityColor(type);

                      return Card(
                        key: ValueKey(t['id']),
                        color: Theme.of(context).colorScheme.surface,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: badgeColor.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              // Left: Title, Stats, and Notes
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Small Activity Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 1),
                                          ),
                                          child: Text(
                                            _getActivityName(type),
                                            style: TextStyle(
                                              color: badgeColor,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if ((t['auto_regulate'] as int? ?? 1) == 1) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 1),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.favorite, size: 8, color: Colors.redAccent),
                                                SizedBox(width: 2),
                                                Text(
                                                  'Auto HR',
                                                  style: TextStyle(
                                                    color: Colors.redAccent,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if ((t['treadmill_workout'] as int? ?? 0) == 1) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.cyan.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.cyan.withValues(alpha: 0.3), width: 1),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.directions_run, size: 8, color: Colors.cyan),
                                                SizedBox(width: 2),
                                                Text(
                                                  'Treadmill',
                                                  style: TextStyle(
                                                    color: Colors.cyan,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Stats and Notes Row
                                    Text(
                                      '${continuous ? 'Open Ended' : '$rounds Rounds'}  •  ${_formatDuration(work)} Work  •  ${rest == 0 ? 'No Rest' : '${_formatDuration(rest)} Rest'}${notes.isNotEmpty ? '  •  $notes' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Right: Action Buttons in a Row
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    onPressed: () => _showWorkoutEditor(template: t),
                                    tooltip: 'Edit Details',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.6),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    onPressed: () => _deleteTemplate(t),
                                    tooltip: 'Delete Workout',
                                  ),
                                  const SizedBox(width: 8),
                                  // Start Button
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => widget.onWorkoutSelected(t),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_arrow, size: 14),
                                        SizedBox(width: 2),
                                        Text('Start', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

