// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  main.dart
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/dashboard_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/review_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/no_shop_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await Firebase.initializeApp();
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
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasData && snapshot.data != null) {
              return const _LoggedInGate();
            }
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}

/// After login: if no shop assigned, show NoShopScreen. Otherwise show app (Pull enabled on Setup when no local data).
class _LoggedInGate extends StatefulWidget {
  const _LoggedInGate();

  @override
  State<_LoggedInGate> createState() => _LoggedInGateState();
}

class _LoggedInGateState extends State<_LoggedInGate> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.hasAssignedShop) {
      return const NoShopScreen();
    }
    return const _RootNav();
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              const DashboardScreen(),
              CaptureScreen(key: _captureKey),   // keyed so we can reach its state
              const ReviewScreen(),
              const SetupScreen(),
            ],
          ),
          _SyncOverlay(),
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

/// Full-screen overlay shown during sync or write. Blocks interaction and shows progress message.
class _SyncOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final syncing = context.watch<AppState>().isSyncingOrWriting;
    if (!syncing) return const SizedBox.shrink();
    return Material(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          color: ZCTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: ZCTheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: ZCTheme.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Synchronisation en cours…',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ZCTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ne quittez pas l\'application.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ZCTheme.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
