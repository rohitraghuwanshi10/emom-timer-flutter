import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'screens/timer_screen.dart';
import 'screens/library_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'services/sync_service.dart';
import 'services/database_helper.dart';
import 'services/bluetooth_service.dart';
import 'services/treadmill_service.dart';
import 'firebase_options.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Silence verbose Bluetooth logs (e.g. FBP-iOS didUpdateValueForCharacteristic)
  FlutterBluePlus.setLogLevel(LogLevel.none, color: false);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Trigger initial background sync
    SyncService.instance.signInAndSync();
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }
  runApp(const EmomTimerApp());
}


class EmomTimerApp extends StatelessWidget {
  const EmomTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ChronoPulse Active Premium Neon Colors (inspired by custom app icon)
    final Color deepBg = const Color(0xFF0C101B);      // Deep Slate Charcoal Blue
    final Color deepSurface = const Color(0xFF171E2D); // Deep Slate Card Surface
    final Color mintNeon = const Color(0xFF0DF2A3);    // Mint Neon Accent (Primary / Go)
    final Color orangeNeon = const Color(0xFFFF7A00);  // Vibrant Orange Accent (Secondary / Rest)
    final Color redNeon = const Color(0xFFFF3B30);     // Neon Red Accent (Stop/Error)
    final Color textPrimary = const Color(0xFFECEFF4);  // White Text
    final Color textSecondary = const Color(0xFF8E9AA8); // Slate Secondary Text

    return MaterialApp(
      title: 'ChronoPulse Active',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: deepBg,
        primaryColor: mintNeon,
        colorScheme: ColorScheme.dark(
          primary: mintNeon,
          secondary: orangeNeon,
          surface: deepSurface,
          error: redNeon,
          onPrimary: deepBg,
          onSecondary: deepBg,
          onSurface: textPrimary,
          onError: textPrimary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: deepSurface,
          elevation: 0,
          titleTextStyle: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: deepSurface,
          selectedItemColor: mintNeon,
          unselectedItemColor: textSecondary.withValues(alpha: 0.6),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}


class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late PageController _pageController;
  final GlobalKey<TimerScreenState> _timerKey = GlobalKey<TimerScreenState>();
  final GlobalKey<LibraryScreenState> _libraryKey = GlobalKey<LibraryScreenState>();
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey<HistoryScreenState>();
  final GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();
  Map<String, dynamic>? _pendingTemplate;

  String _profileName = 'Default';
  List<String> _availableProfiles = [];
  StreamSubscription? _hrSub;
  StreamSubscription? _treadmillSub;
  bool _isBluetoothConnected = false;
  bool _isTreadmillConnected = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    
    // Load active profile data
    _loadProfileData();

    // Check initial connection states
    _isBluetoothConnected = AppBluetoothService.instance.isConnected;
    _isTreadmillConnected = TreadmillBluetoothService.instance.isConnected;

    // Listen to changes
    _hrSub = AppBluetoothService.instance.deviceStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isBluetoothConnected = state == BluetoothConnectionState.connected;
        });
      }
    });

    _treadmillSub = TreadmillBluetoothService.instance.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isTreadmillConnected = state == BluetoothConnectionState.connected;
        });
      }
    });
  }

  @override
  void dispose() {
    _hrSub?.cancel();
    _treadmillSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final active = await DatabaseHelper.instance.getActiveProfileName();
    List<String> profileNames = ['Default'];
    try {
      final db = await DatabaseHelper.instance.database;
      final res = await db.query('profiles');
      if (res.isNotEmpty) {
        profileNames = res.map((row) => row['name'] as String).toList();
      }
    } catch (e) {
      debugPrint('Error getting profiles: $e');
    }
    if (mounted) {
      setState(() {
        _profileName = active;
        _availableProfiles = profileNames;
      });
    }
  }

  Future<void> _switchProfile(String name) async {
    await DatabaseHelper.instance.setActiveProfileName(name);
    await _loadProfileData();
    // Notify all active screen controllers to reload
    _timerKey.currentState?.loadProfileSettings();
    _libraryKey.currentState?.loadTemplates();
    _historyKey.currentState?.refreshHistory();
    _profileKey.currentState?.loadProfile();
  }

  Widget _buildProfileSelectorAction() {
    if (_availableProfiles.isEmpty) {
      return PopupMenuButton<String>(
        onSelected: _switchProfile,
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'Default',
            child: Text('Default'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.person, size: 16),
        ),
      );
    }

    return PopupMenuButton<String>(
      onSelected: _switchProfile,
      tooltip: 'Switch Profile',
      itemBuilder: (context) {
        return _availableProfiles.map((String profile) {
          return PopupMenuItem<String>(
            value: profile,
            child: Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: profile == _profileName ? Theme.of(context).colorScheme.primary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  profile,
                  style: TextStyle(
                    fontWeight: profile == _profileName ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person, size: 16),
            const SizedBox(height: 2),
            Text(
              _profileName,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothAction() {
    final bool isConnected = _isBluetoothConnected || _isTreadmillConnected;
    return IconButton(
      icon: Icon(
        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
        color: isConnected ? Theme.of(context).colorScheme.primary : Colors.grey,
        size: 20,
      ),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const BluetoothDeviceManagerSheet(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape && MediaQuery.of(context).size.height < 500;

    final Widget mainBody = PageView(
      controller: _pageController,
      physics: (Platform.isIOS || Platform.isAndroid)
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
        if (index == 0) {
          _timerKey.currentState?.loadProfileSettings();
          if (_pendingTemplate != null) {
            _timerKey.currentState?.loadTemplate(_pendingTemplate!);
            _pendingTemplate = null;
          }
        } else if (index == 1) {
          _libraryKey.currentState?.loadTemplates();
        } else if (index == 2) {
          _historyKey.currentState?.refreshHistory();
          SyncService.instance.signInAndSync().then((success) {
            if (success && mounted && _currentIndex == 2) {
              _historyKey.currentState?.refreshHistory();
            }
          });
        } else if (index == 3) {
          _profileKey.currentState?.loadProfile();
        }
      },
      children: [
        TimerScreen(key: _timerKey),
        LibraryScreen(
          key: _libraryKey,
          onWorkoutSelected: (template) {
            _pendingTemplate = template;
            if (_timerKey.currentState != null) {
              _timerKey.currentState!.loadTemplate(template);
              _pendingTemplate = null;
            }
            _pageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
        ),
        HistoryScreen(key: _historyKey),
        ProfileScreen(key: _profileKey),
      ],
    );

    return Scaffold(
      body: isLandscape
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: 0.0,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  selectedIconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
                  selectedLabelTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  unselectedIconTheme: const IconThemeData(color: Colors.grey),
                  unselectedLabelTextStyle: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.timer_outlined),
                      selectedIcon: Icon(Icons.timer),
                      label: Text('Timer'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.fitness_center_outlined),
                      selectedIcon: Icon(Icons.fitness_center),
                      label: Text('Library'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.bar_chart_outlined),
                      selectedIcon: Icon(Icons.bar_chart),
                      label: Text('History'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: Text('Profile'),
                    ),
                  ],
                  trailing: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildBluetoothAction(),
                        const SizedBox(height: 4),
                        _buildProfileSelectorAction(),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                ),
                Expanded(child: mainBody),
              ],
            )
          : mainBody,
      bottomNavigationBar: isLandscape
          ? null
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              type: BottomNavigationBarType.fixed,
              onTap: (index) {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.timer),
                  label: 'Timer',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.fitness_center),
                  label: 'Library',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bar_chart),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
    );
  }
}
