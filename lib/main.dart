// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  main.dart
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/dashboard_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/review_screen.dart';
import 'screens/setup_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // Request public storage access (Android 11+)
  if (Platform.isAndroid) {
    final status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }
    await Permission.storage.request();
  }
  runApp(const ZeroCleanApp());
}

class ZeroCleanApp extends StatelessWidget {
  const ZeroCleanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'Zero-Clean',
        theme: ZCTheme.theme,
        debugShowCheckedModeBanner: false,
        home: const _RootNav(),
      ),
    );
  }
}

class _RootNav extends StatefulWidget {
  const _RootNav();

  @override
  State<_RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<_RootNav> {
  int _currentIndex = 0;

  // Key gives us access to CaptureScreen's state so we can
  // call activate() / deactivate() when tabs switch.
  final _captureKey = GlobalKey<CaptureScreenState>();

  static const int _captureTabIndex = 1;

  void _onTabTapped(int index) {
    // Leaving capture tab → release camera
    if (_currentIndex == _captureTabIndex && index != _captureTabIndex) {
      _captureKey.currentState?.deactivate();
    }
    // Entering capture tab → start camera
    if (index == _captureTabIndex && _currentIndex != _captureTabIndex) {
      _captureKey.currentState?.activate();
    }
    setState(() => _currentIndex = index);
    // Refresh from DB after this frame so we don't trigger layout during build
    if (index == 0 || index == 2 || index == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().refreshFromDatabase();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const DashboardScreen(),
          CaptureScreen(key: _captureKey),   // keyed so we can reach its state
          const ReviewScreen(),
          const SetupScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ZCTheme.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Capture',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.photo_library_outlined),
              activeIcon: Icon(Icons.photo_library),
              label: 'Review',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune_outlined),
              activeIcon: Icon(Icons.tune),
              label: 'Setup',
            ),
          ],
        ),
      ),
    );
  }
}
