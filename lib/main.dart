import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/timer_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
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
    // Nord Theme Colors
    final Color nord0 = const Color(0xFF2E3440); // Polar Night (Background)
    final Color nord1 = const Color(0xFF3B4252);
    final Color nord4 = const Color(0xFFD8DEE9); // Snow Storm (Text)
    final Color nord6 = const Color(0xFFECEFF4);
    final Color nord8 = const Color(0xFF88C0D0); // Frost (Accent)
    final Color nord11 = const Color(0xFFBF616A); // Aurora (Red/Stop)
    final Color nord14 = const Color(0xFFA3BE8C); // Aurora (Green/Go)

    return MaterialApp(
      title: 'ChronoPulse Active',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: nord0,
        primaryColor: nord8,
        colorScheme: ColorScheme.dark(
          primary: nord8,
          secondary: nord14,
          surface: nord1,
          error: nord11,
          onPrimary: nord0,
          onSecondary: nord0,
          onSurface: nord4,
          onError: nord6,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: nord1,
          elevation: 0,
          titleTextStyle: TextStyle(color: nord6, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: nord1,
          selectedItemColor: nord8,
          unselectedItemColor: nord4.withValues(alpha: 0.6),
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
