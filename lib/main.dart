import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/timer_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmomTimerApp());
}

class EmomTimerApp extends StatelessWidget {
  const EmomTimerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Nord Theme Colors
    final Color nord0 = const Color(0xFF2E3440); // Polar Night (Background)
    final Color nord1 = const Color(0xFF3B4252);
    final Color nord2 = const Color(0xFF434C5E);
    final Color nord3 = const Color(0xFF4C566A);
    final Color nord4 = const Color(0xFFD8DEE9); // Snow Storm (Text)
    final Color nord6 = const Color(0xFFECEFF4);
    final Color nord8 = const Color(0xFF88C0D0); // Frost (Accent)
    final Color nord11 = const Color(0xFFBF616A); // Aurora (Red/Stop)
    final Color nord14 = const Color(0xFFA3BE8C); // Aurora (Green/Go)

    return MaterialApp(
      title: 'EMOM Timer',
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
          unselectedItemColor: nord3,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const TimerScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
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
