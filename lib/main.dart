import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'screens/timer_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'services/sync_service.dart';
import 'firebase_options.dart';

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
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey<HistoryScreenState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
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
          } else if (index == 1) {
            _historyKey.currentState?.refreshHistory();
            SyncService.instance.signInAndSync().then((success) {
              if (success && mounted && _currentIndex == 1) {
                _historyKey.currentState?.refreshHistory();
              }
            });
          }
        },
        children: [
          TimerScreen(key: _timerKey),
          HistoryScreen(key: _historyKey),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
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
