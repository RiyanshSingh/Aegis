import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'services/google_drive_service.dart';
import 'services/vault_crypto.dart';
import 'services/app_update_service.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? true;
  runApp(SecureVaultApp(initialIsDark: isDark));
}

class AppColors {
  static const darkBg = Color(0xFF131314); 
  static const darkCard = Color(0xFF1E1F20); 
  static const lightBg = Color(0xFFF7F9FC);
  static const lightCard = Colors.white;
}

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(ThemeMode value) : super(value);
  void toggle() async {
    value = value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDark', value == ThemeMode.dark);
  }
}

class SecureVaultApp extends StatefulWidget {
  final bool initialIsDark;
  const SecureVaultApp({super.key, required this.initialIsDark});
  @override
  State<SecureVaultApp> createState() => _SecureVaultAppState();
  static ThemeController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ThemeInheritedWidget>()!.controller;
}

class _SecureVaultAppState extends State<SecureVaultApp> with WidgetsBindingObserver {
  late ThemeController _themeController;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeController = ThemeController(widget.initialIsDark ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _lifecycleState = state;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ThemeInheritedWidget(
      controller: _themeController,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _themeController,
        builder: (context, themeMode, _) {
          return MaterialApp(
            key: const Key('aegis_root_app'),
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            title: 'Aegis',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            builder: (context, child) {
              final isBlurred = _lifecycleState != AppLifecycleState.resumed;
              return Stack(
                children: [
                  if (child != null) child,
                  if (isBlurred)
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          color: Colors.black.withOpacity(0.2),
                          child: const Center(
                            child: Icon(Icons.wallet, size: 80, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorScheme: const ColorScheme.light(
                primary: Colors.black,
                onPrimary: Colors.white,
                secondary: Colors.black,
                onSecondary: Colors.white,
                surface: AppColors.lightBg,
                onSurface: Colors.black,
              ),
              scaffoldBackgroundColor: AppColors.lightBg,
              appBarTheme: const AppBarTheme(backgroundColor: AppColors.lightBg, elevation: 0, foregroundColor: Colors.black, centerTitle: false),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: const ColorScheme.dark(
                primary: Colors.white,
                onPrimary: Colors.black,
                secondary: Colors.white,
                onSecondary: Colors.black,
                surface: AppColors.darkBg,
                onSurface: Colors.white,
              ),
              scaffoldBackgroundColor: AppColors.darkBg,
              appBarTheme: const AppBarTheme(backgroundColor: AppColors.darkBg, elevation: 0, foregroundColor: Colors.white, centerTitle: false),
            ),
            home: const AegisSplashScreen(),
          );
        },
      ),
    );
  }
}

class _ThemeInheritedWidget extends InheritedWidget {
  final ThemeController controller;
  const _ThemeInheritedWidget({required this.controller, required super.child});
  @override
  bool updateShouldNotify(_ThemeInheritedWidget oldWidget) => controller != oldWidget.controller;
}

// --- Models ---
class SecretItem {
  final String id;
  final String title;
  final String username;
  final String secret;
  final bool isCard;
  final String category;
  final String cardType;
  final String cvv;
  final String cardProvider;
  final String expiryDate;

  SecretItem({
    required this.id, required this.title, required this.username, required this.secret, 
    required this.isCard, this.category = 'Other', this.cardType = 'Credit', this.cvv = '',
    this.cardProvider = 'Auto', this.expiryDate = ''
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'title': title, 'username': username, 'secret': secret, 
    'isCard': isCard, 'category': category, 'cardType': cardType, 'cvv': cvv,
    'cardProvider': cardProvider, 'expiryDate': expiryDate
  };

  factory SecretItem.fromMap(Map<String, dynamic> map) => SecretItem(
    id: map['id'], title: map['title'], username: map['username'], secret: map['secret'], 
    isCard: map['isCard'] ?? false, category: map['category'] ?? 'Other', 
    cardType: map['cardType'] ?? 'Credit', cvv: map['cvv'] ?? '',
    cardProvider: map['cardProvider'] ?? 'Auto', expiryDate: map['expiryDate'] ?? ''
  );
}

// --- Animated Open-to-Close Lock Widget ---
class AnimatedLockWidget extends StatelessWidget {
  final Animation<double> lockProgress;
  final Animation<double> bounceProgress;
  final Color color;
  final double size;

  const AnimatedLockWidget({
    super.key,
    required this.lockProgress,
    required this.bounceProgress,
    required this.color,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([lockProgress, bounceProgress]),
      builder: (context, _) {
        final t = lockProgress.value;
        final bounce = bounceProgress.value;

        // When open (t = 0.0): Shackle translated up and angled open
        // When closed (t = 1.0): Shackle flush in the lock body
        final shackleY = (1.0 - t) * -16.0;
        final shackleAngle = (1.0 - t) * -0.28;

        return Transform.scale(
          scale: 1.0 + (bounce * 0.08),
          child: SizedBox(
            width: size * 1.1,
            height: size * 1.35,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                // Lock Shackle (Top U-loop)
                Positioned(
                  top: 4 + shackleY,
                  child: Transform.rotate(
                    angle: shackleAngle,
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: size * 0.52,
                      height: size * 0.62,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(size * 0.26)),
                        border: Border.all(
                          color: color,
                          width: size * 0.09,
                        ),
                      ),
                    ),
                  ),
                ),
                // Lock Body (Solid clean rounded rectangle)
                Container(
                  width: size * 0.88,
                  height: size * 0.68,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(size * 0.20),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: size * 0.12,
                          height: size * 0.12,
                          decoration: BoxDecoration(
                            color: color == Colors.white ? const Color(0xFF0F1012) : Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: size * 0.06,
                          height: size * 0.09,
                          decoration: BoxDecoration(
                            color: color == Colors.white ? const Color(0xFF0F1012) : Colors.white,
                            borderRadius: BorderRadius.circular(size * 0.03),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

void showLuxuryNotification(
  BuildContext? context, {
  required String title,
  required String message,
  bool isError = false,
  IconData? icon,
}) {
  final messenger = rootScaffoldMessengerKey.currentState ?? (context != null ? ScaffoldMessenger.maybeOf(context) : null);
  if (messenger == null) return;
  
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 4),
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF121214),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isError
                ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                    : const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? (isError ? Icons.error_outline_rounded : Icons.check_circle_rounded),
                color: isError ? const Color(0xFFF87171) : const Color(0xFF34D399),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// --- Minimal Luxury Brand Splash ---
class AegisSplashScreen extends StatefulWidget {
  const AegisSplashScreen({super.key});
  @override
  State<AegisSplashScreen> createState() => _AegisSplashScreenState();
}

class _AegisSplashScreenState extends State<AegisSplashScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _lockController;
  late AnimationController _bounceController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _lockAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    // Fade in
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    // Lock closing transition
    _lockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _lockAnimation = CurvedAnimation(parent: _lockController, curve: Curves.easeInOutCubic);

    // Subtle impact snap
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
    ]).animate(_bounceController);

    _fadeController.forward();
    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Brief pause with lock open
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    // 2. Animate lock from open to close
    _lockController.forward();
    await Future.delayed(const Duration(milliseconds: 480));
    if (!mounted) return;

    // 3. Snap feedback
    HapticFeedback.mediumImpact();
    _bounceController.forward(from: 0.0);

    // 4. Clean pause to display closed lock & Aegis branding
    await Future.delayed(const Duration(milliseconds: 550));

    final prefs = await SharedPreferences.getInstance();
    final hasOnboarded = prefs.getBool('hasOnboarded') ?? false;
    final storage = const FlutterSecureStorage();
    final pin = await storage.read(key: 'master_pin');

    if (!mounted) return;
    if (!hasOnboarded) {
      Navigator.pushReplacement(context, FadeScaleRoute(page: const OnboardingScreen()));
    } else if (pin == null) {
      Navigator.pushReplacement(context, FadeScaleRoute(page: const PinSetupScreen()));
    } else {
      Navigator.pushReplacement(context, FadeScaleRoute(page: const PinUnlockScreen()));
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _lockController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fgColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1012) : const Color(0xFFF7F8FA),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Open to close animated lock with transparent background
              AnimatedLockWidget(
                lockProgress: _lockAnimation,
                bounceProgress: _bounceAnimation,
                color: fgColor,
                size: 58,
              ),
              const SizedBox(height: 28),
              // Only "Aegis"
              Text(
                'Aegis',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasOnboarded', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PinSetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131314) : Colors.white,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            children: [
              _buildPage(
                Icons.shield_rounded, 
                'Bank-grade\nSecurity', 
                'Your data is protected by military-grade AES-256 encryption. We utilize a zero-knowledge architecture, meaning only you have the keys to your vault.', 
                isDark,
                isDark ? Colors.white : Colors.black,
              ),
              _buildPage(
                Icons.account_balance_wallet_rounded, 
                'All your assets\nin one place', 
                'Securely store your credit cards, debit cards, passwords, and sensitive notes. Access them instantly with local biometric authentication.', 
                isDark,
                const Color(0xFF67C7A8)
              ),
              _buildPage(
                Icons.phonelink_lock_rounded, 
                '100% Offline\n& Local', 
                'Your data never leaves your device. No cloud sync, no tracking, no servers. Absolute privacy guaranteed.', 
                isDark,
                const Color(0xFFE8B79B)
              ),
            ],
          ),
          Positioned(
            bottom: 48, left: 32, right: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(3, (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 8),
                    width: _currentPage == index ? 32 : 8, height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index ? (isDark ? Colors.white : Colors.black) : Colors.grey.withOpacity(0.3), 
                      borderRadius: BorderRadius.circular(4)
                    ),
                  )),
                ),
                GestureDetector(
                  onTap: () {
                    if (_currentPage < 2) _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
                    else _finish();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : Colors.black, 
                      borderRadius: BorderRadius.circular(30)
                    ),
                    child: Text(
                      _currentPage == 2 ? 'Get Started' : 'Next', 
                      style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
  Widget _buildPage(IconData icon, String title, String desc, bool isDark, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(28)),
            child: Icon(icon, size: 64, color: iconColor),
          ),
          const SizedBox(height: 48),
          Text(title, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 24),
          Text(desc, style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.6, fontWeight: FontWeight.w500)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// --- PIN Setup ---
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}
class _PinSetupScreenState extends State<PinSetupScreen> {
  String _pin = '';
  void _addNumber(String number) {
    HapticFeedback.lightImpact();
    if (_pin.length < 4) setState(() => _pin += number);
  }
  void _deleteNumber() {
    HapticFeedback.lightImpact();
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }
  void _savePin() async {
    if (_pin.length == 4) {
      final storage = const FlutterSecureStorage();
      await storage.write(key: 'master_pin', value: _pin);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasOnboarded', true);
      if (!mounted) return;
      Navigator.pushReplacement(context, FadeScaleRoute(page: const MainTabScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131314) : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                const Text('Set Master PIN', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                const Text('This PIN protects all your data locally.', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 40),
                Text(('●' * _pin.length).padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 48),
                _buildKeypad(isDark),
                const SizedBox(height: 48),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pin.length == 4 ? (isDark ? Colors.white : Colors.black) : (isDark ? AppColors.darkCard : Colors.grey[200]), 
                    foregroundColor: isDark ? Colors.black : Colors.white, 
                    minimumSize: const Size(200, 56), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), 
                    elevation: 0
                  ),
                  onPressed: _pin.length == 4 ? _savePin : null,
                  child: Text('Confirm PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _pin.length == 4 ? (isDark ? Colors.black : Colors.white) : Colors.grey)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildKeypad(bool isDark) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var j = 1; j <= 3; j++) _buildKey((i * 3 + j).toString(), isDark)]),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 70, height: 70),
            const SizedBox(width: 16),
            _buildKey('0', isDark),
            const SizedBox(width: 16),
            GestureDetector(onTap: _deleteNumber, child: Container(width: 70, height: 70, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)), child: const Icon(Icons.backspace_rounded, size: 24))),
          ],
        ),
      ],
    );
  }
  Widget _buildKey(String number, bool isDark) {
    return GestureDetector(
      onTap: () => _addNumber(number),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 70, height: 70, alignment: Alignment.center, 
        decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        child: Text(number, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
    );
  }
}

bool isCurrentlyEditing = false;

// --- PIN Unlock ---
class PinUnlockScreen extends StatefulWidget {
  final bool isOverlay;
  const PinUnlockScreen({super.key, this.isOverlay = false});
  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}
class _PinUnlockScreenState extends State<PinUnlockScreen> {
  String _pin = '';
  bool _isError = false;
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();
      if (canAuthenticate) {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Authenticate to unlock your wallet',
        );
        if (didAuthenticate) _unlock();
      }
    } catch (e) {
      debugPrint('Biometrics error: $e');
    }
  }

  void _addNumber(String number) async {
    HapticFeedback.lightImpact();
    if (_pin.length < 4) {
      setState(() { _pin += number; _isError = false; });
      if (_pin.length == 4) _verifyPin();
    }
  }
  void _deleteNumber() {
    HapticFeedback.lightImpact();
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }
  void _verifyPin() async {
    final storage = const FlutterSecureStorage();
    final savedPin = await storage.read(key: 'master_pin');
    if (_pin == savedPin) {
      _unlock();
    } else {
      setState(() { _isError = true; _pin = ''; });
    }
  }
  void _unlock() {
    if (!mounted) return;
    if (widget.isOverlay && Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(context, FadeScaleRoute(page: const MainTabScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131314) : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.lock_rounded, size: 48, color: isDark ? Colors.white : Colors.black87),
                const SizedBox(height: 24),
                const Text('Welcome Back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Text(_isError ? 'Incorrect PIN, try again' : 'Enter your Master PIN', style: TextStyle(color: _isError ? Colors.redAccent : Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 40),
                Text(('●' * _pin.length).padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold, color: _isError ? Colors.redAccent : (isDark ? Colors.white : Colors.black87))),
                const SizedBox(height: 48),
                _buildKeypad(isDark),
                const SizedBox(height: 32),
                IconButton(
                  icon: const Icon(Icons.fingerprint, size: 36),
                  color: isDark ? Colors.white : Colors.black87,
                  onPressed: _checkBiometrics,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildKeypad(bool isDark) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var j = 1; j <= 3; j++) _buildKey((i * 3 + j).toString(), isDark)]),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 70, height: 70),
            const SizedBox(width: 16),
            _buildKey('0', isDark),
            const SizedBox(width: 16),
            GestureDetector(onTap: _deleteNumber, child: Container(width: 70, height: 70, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)), child: const Icon(Icons.backspace_rounded, size: 24))),
          ],
        ),
      ],
    );
  }
  Widget _buildKey(String number, bool isDark) {
    return GestureDetector(
      onTap: () => _addNumber(number),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 70, height: 70, alignment: Alignment.center, 
        decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        child: Text(number, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
    );
  }
}
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});
  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}
class _MainTabScreenState extends State<MainTabScreen> with WidgetsBindingObserver {
  DateTime? _pausedTime;
  final storage = const FlutterSecureStorage();
  bool _isLockShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          AppUpdateService.instance.checkForUpdate(context, silent: true);
        }
      });
    });
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (isCurrentlyEditing) {
        // While user is entering/editing details on AddEditItemPage,
        // switching apps to copy/verify details will NOT lock or restart the page.
        _pausedTime = null;
        return;
      }
      if (_pausedTime != null) {
        final lockType = await storage.read(key: 'auto_lock') ?? 'Immediate';
        final diff = DateTime.now().difference(_pausedTime!);
        bool shouldLock = false;
        if (lockType == 'Immediate') shouldLock = true;
        else if (lockType == '1 Minute' && diff.inSeconds > 60) shouldLock = true;
        else if (lockType == '5 Minutes' && diff.inSeconds > 300) shouldLock = true;
        
        if (shouldLock && !_isLockShowing) {
          if (mounted) {
            _isLockShowing = true;
            await Navigator.push(context, FadeScaleRoute(page: const PinUnlockScreen(isOverlay: true)));
            _isLockShowing = false;
          }
        }
        _pausedTime = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}

// --- Home Screen (Google Wallet Style) ---

class UniversalCardWidget extends StatelessWidget {
  final String bankName;
  final String cardType;
  final String secret;
  final String cardholderName;
  final String expiryDate;
  final String cardProvider;
  final bool isMasked;

  const UniversalCardWidget({
    super.key,
    required this.bankName,
    required this.cardType,
    required this.secret,
    required this.cardholderName,
    required this.expiryDate,
    required this.cardProvider,
    this.isMasked = false,
  });

  String _insertSpaces(String text) {
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i + 1) % 4 == 0 && (i + 1) != text.length) buffer.write(' ');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    Widget logo = const SizedBox();
    String detected = cardProvider;
    if (detected == 'Auto') {
      final String normalized = secret.replaceAll(' ', '');
      if (normalized.startsWith('4')) {
        detected = 'Visa';
      } else if (normalized.startsWith('5') || normalized.startsWith('2')) {
        detected = 'Mastercard';
      } else if (normalized.startsWith('6')) {
        detected = 'RuPay';
      }
    }
    
    if (detected == 'Visa') {
      logo = const Text('VISA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, fontStyle: FontStyle.italic));
    } else if (detected == 'Mastercard') {
      logo = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), shape: BoxShape.circle)),
          Transform.translate(offset: const Offset(-10, 0), child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), shape: BoxShape.circle))),
        ],
      );
    } else if (detected == 'RuPay') {
      logo = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Ru', style: TextStyle(color: Color(0xFFE35205), fontWeight: FontWeight.w900, fontSize: 20, fontStyle: FontStyle.italic)),
          Text('Pay', style: TextStyle(color: Color(0xFF1A1F71), fontWeight: FontWeight.w900, fontSize: 20, fontStyle: FontStyle.italic)),
        ],
      );
    }

    final String displayBank = (bankName.isEmpty ? 'BANK NAME' : bankName).toUpperCase();
    final String displayName = (cardholderName.isEmpty ? 'JOHN DOE' : cardholderName).toUpperCase();

    String displaySecret;
    if (isMasked) {
      final clean = secret.replaceAll(' ', '');
      if (clean.isEmpty) {
        displaySecret = '**** **** **** 0329';
      } else if (clean.length <= 4) {
        displaySecret = '**** **** **** $clean';
      } else {
        final last4 = clean.substring(clean.length - 4);
        displaySecret = '**** **** **** $last4';
      }
    } else {
      displaySecret = secret.isEmpty ? '8763 2736 9873 0329' : _insertSpaces(secret);
    }

    final String displayExpiry = isMasked ? '**/**' : (expiryDate.isEmpty ? '10/28' : expiryDate);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFE8B79B), Color(0xFF67C7A8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: 152,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(displayBank, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(cardType, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const Icon(Icons.contactless_rounded, color: Colors.white),
                        ],
                      ),
                      Text(
                        displaySecret, 
                        style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700)
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Card Holder Name', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                                Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Expired Date', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                                Text(displayExpiry, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 60,
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: logo,
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final storage = const FlutterSecureStorage();
  List<SecretItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dataStr = await storage.read(key: 'vault_data');
    if (dataStr != null) {
      final List<dynamic> decoded = jsonDecode(dataStr);
      _items = decoded.map((e) => SecretItem.fromMap(e)).toList();
      _items.sort((a, b) => b.id.compareTo(a.id));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cards = _items.where((e) => e.isCard).toList();
    final passes = _items.where((e) => !e.isCard).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.account_balance_wallet, color: isDark ? Colors.white : Colors.black),
            const SizedBox(width: 12),
            Text('Wallet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 22, color: isDark ? Colors.white : Colors.black)),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push(context, FadeScaleRoute(page: const SettingsScreenWrapper()));
              if (result == true) _loadData();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 36, height: 36,
              decoration: BoxDecoration(color: isDark ? Colors.white : Colors.black, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('R', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          )
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                if (cards.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 24, right: 24, top: 48, bottom: 32),
                      child: EmptyVaultState(isDark: isDark, isCardsView: true, onAdd: () async {
                        final result = await Navigator.push(context, FadeScaleRoute(page: const AddEditItemPage()));
                        if (result == true) _loadData();
                      }),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 200,
                      child: PageView.builder(
                        controller: PageController(viewportFraction: 0.85),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: GestureDetector(
                              onTap: () async {
                                final authenticated = await _promptItemPin(context, isCard: true);
                                if (authenticated == true) {
                                  if (!context.mounted) return;
                                  final result = await Navigator.push(context, FadeScaleRoute(page: ViewItemScreen(item: cards[index])));
                                  if (result == true) _loadData();
                                }
                              },
                              child: Hero(
                                tag: 'hero-${cards[index].id}',
                                child: Material(
                                  color: Colors.transparent,
                                  child: _buildGoogleCard(cards[index], isDark),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                if (passes.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Text('Credentials', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    ),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: VaultItemTile(
                          item: passes[index],
                          onTap: () async {
                            final authenticated = await _promptItemPin(context, isCard: false);
                            if (authenticated == true) {
                              if (!context.mounted) return;
                              final result = await Navigator.push(context, FadeScaleRoute(page: ViewItemScreen(item: passes[index])));
                              if (result == true) _loadData();
                            }
                          },
                        ),
                      );
                    },
                    childCount: passes.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
        onPressed: () async {
          final result = await Navigator.push(context, FadeScaleRoute(page: const AddEditItemPage()));
          if (result == true) _loadData();
        },
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Future<bool> _promptItemPin(BuildContext context, {required bool isCard}) async {
    final expectedPin = isCard
        ? (await storage.read(key: 'card_pin') ?? await storage.read(key: 'master_pin'))
        : (await storage.read(key: 'pass_pin') ?? await storage.read(key: 'master_pin'));

    if (expectedPin == null || expectedPin.isEmpty) return true;

    if (!context.mounted) return false;

    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        String input = '';
        bool isError = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(isCard ? 'Unlock Card' : 'Unlock Password', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isError 
                        ? (isCard ? 'Incorrect Card PIN, try again' : 'Incorrect Password PIN, try again')
                        : (isCard ? 'Enter Card PIN to view card details' : 'Enter PIN to view password details'), 
                    style: TextStyle(color: isError ? Colors.redAccent : Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ('●' * input.length).padRight(4, '○'), 
                    style: TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: isError ? Colors.redAccent : (isDark ? Colors.white : Colors.black))
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                    children: List.generate(12, (i) {
                      if (i == 9) {
                        return const SizedBox(width: 64, height: 64);
                      }
                      if (i == 11) {
                        return GestureDetector(
                          onTap: () {
                            if (input.isNotEmpty) {
                              setDialogState(() {
                                input = input.substring(0, input.length - 1);
                                isError = false;
                              });
                            }
                          },
                          child: Container(
                            width: 64, height: 64,
                            alignment: Alignment.center,
                            child: const Icon(Icons.backspace_outlined, size: 22),
                          ),
                        );
                      }
                      final n = i == 10 ? 0 : i + 1;
                      return GestureDetector(
                        onTap: () {
                          if (input.length < 4) {
                            setDialogState(() {
                              input += n.toString();
                              isError = false;
                            });
                            if (input.length == 4) {
                              if (input == expectedPin) {
                                Navigator.pop(context, input);
                              } else {
                                HapticFeedback.heavyImpact();
                                setDialogState(() {
                                  isError = true;
                                  input = '';
                                });
                              }
                            }
                          }
                        },
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                          alignment: Alignment.center,
                          child: Text(n.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                  )
                ],
              ),
            );
          }
        );
      }
    );

    return result == expectedPin;
  }

  Widget _buildGoogleCard(SecretItem item, bool isDark) {
    return UniversalCardWidget(
      bankName: item.title,
      cardType: item.cardType,
      secret: item.secret,
      cardholderName: item.username,
      expiryDate: item.expiryDate,
      cardProvider: item.cardProvider,
      isMasked: true,
    );
  }
}

class SettingsScreenWrapper extends StatelessWidget {
  const SettingsScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const SettingsView(),
    );
  }
}


class SettingsView extends StatefulWidget {
  const SettingsView({super.key});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final storage = const FlutterSecureStorage();
  bool _useBiometrics = false;
  String _autoLock = 'Immediate';
  String? _googleEmail;
  String? _lastSyncText;
  bool _isGoogleDriveBusy = false;
  bool _isCheckingUpdates = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final b = await storage.read(key: 'use_biometrics');
    final a = await storage.read(key: 'auto_lock');
    final savedEmail = await GoogleDriveService.instance.getSavedEmail();
    final lastSync = await GoogleDriveService.instance.getLastSyncFormatted();

    if (mounted) {
      setState(() {
        _useBiometrics = b == 'true';
        _autoLock = a ?? 'Immediate';
        _googleEmail = savedEmail;
        _lastSyncText = lastSync;
      });
    }

    try {
      final account = await GoogleDriveService.instance.initSilentSignIn();
      if (account != null && mounted) {
        setState(() {
          _googleEmail = account;
        });
      }
    } catch (_) {}
  }

  Future<void> _changePin() async {
    final newPin = await showDialog<String>(
      context: context,
      builder: (context) {
        String input = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Set New Master PIN', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter 4-digit PIN', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  Text(('●' * input.length).padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                    children: List.generate(11, (i) {
                      if (i == 9) return const SizedBox(width: 64, height: 64);
                      final n = i == 10 ? 0 : i + 1;
                      return GestureDetector(
                        onTap: () {
                          if (input.length < 4) {
                            setState(() => input += n.toString());
                            if (input.length == 4) Future.delayed(const Duration(milliseconds: 300), () => Navigator.pop(context, input));
                          }
                        },
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                          alignment: Alignment.center,
                          child: Text(n.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                  )
                ],
              ),
            );
          }
        );
      }
    );

    if (newPin != null && newPin.length == 4) {
      await storage.write(key: 'master_pin', value: newPin);
      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Master PIN updated successfully!', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)), 
            backgroundColor: isDark ? Colors.white : Colors.black, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _changeCardPin() async {
    String input = '';
    final newPin = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Set Card PIN', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter 4-digit PIN for unlocking cards', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  Text(('●' * input.length).padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                    children: List.generate(11, (i) {
                      if (i == 9) return const SizedBox(width: 64, height: 64);
                      final n = i == 10 ? 0 : i + 1;
                      return GestureDetector(
                        onTap: () {
                          if (input.length < 4) {
                            setState(() => input += n.toString());
                            if (input.length == 4) Future.delayed(const Duration(milliseconds: 300), () => Navigator.pop(context, input));
                          }
                        },
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                          alignment: Alignment.center,
                          child: Text(n.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                  )
                ],
              ),
            );
          }
        );
      }
    );

    if (newPin != null && newPin.length == 4) {
      await storage.write(key: 'card_pin', value: newPin);
      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Card PIN updated successfully!', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)), 
            backgroundColor: isDark ? Colors.white : Colors.black, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _changePasswordPin() async {
    String input = '';
    final newPin = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text('Set Password PIN', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter 4-digit PIN for unlocking passwords', style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  Text(('●' * input.length).padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                    children: List.generate(11, (i) {
                      if (i == 9) return const SizedBox(width: 64, height: 64);
                      final n = i == 10 ? 0 : i + 1;
                      return GestureDetector(
                        onTap: () {
                          if (input.length < 4) {
                            setState(() => input += n.toString());
                            if (input.length == 4) Future.delayed(const Duration(milliseconds: 300), () => Navigator.pop(context, input));
                          }
                        },
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                          alignment: Alignment.center,
                          child: Text(n.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                  )
                ],
              ),
            );
          }
        );
      }
    );

    if (newPin != null && newPin.length == 4) {
      await storage.write(key: 'pass_pin', value: newPin);
      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password PIN updated successfully!', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)), 
            backgroundColor: isDark ? Colors.white : Colors.black, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _changeAutoLock() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SimpleDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Auto-Lock Timeout', style: TextStyle(fontWeight: FontWeight.bold)),
          children: ['Immediate', '1 Minute', '5 Minutes'].map((e) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(e, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
            );
          }).toList(),
        );
      }
    );
    if (result != null) {
      setState(() => _autoLock = result);
      await storage.write(key: 'auto_lock', value: result);
    }
  }


  Future<String?> _promptPasswordDialog(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool isExport = false,
    String? masterPin,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePass = true;
    bool obscureConfirm = true;
    String? errorMsg;
    bool useMasterPin = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.shield_rounded, size: 36, color: isDark ? Colors.white : Colors.black),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 20),

                      if (isExport && masterPin != null && masterPin.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              useMasterPin = !useMasterPin;
                              errorMsg = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: useMasterPin 
                                  ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: useMasterPin 
                                    ? (isDark ? Colors.white : Colors.black) 
                                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  useMasterPin ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                  color: isDark ? Colors.white : Colors.black,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Use Master PIN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (!useMasterPin) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text(
                                isExport ? 'Custom Encryption Password' : 'File Password or PIN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                            TextField(
                              controller: passCtrl,
                              obscureText: obscurePass,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: isExport ? 'Enter strong password' : 'Enter password or PIN',
                                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility, size: 20),
                                  onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                                ),
                                filled: true,
                                fillColor: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.08),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              ),
                            ),
                          ],
                        ),
                        if (isExport) ...[
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'Confirm Password',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                              TextField(
                                controller: confirmCtrl,
                                obscureText: obscureConfirm,
                                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Re-enter password',
                                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                                  prefixIcon: const Icon(Icons.lock_reset, size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility, size: 20),
                                    onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                                  ),
                                  filled: true,
                                  fillColor: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.08),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],

                      if (errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogCtx),
                              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.white : Colors.black,
                                foregroundColor: isDark ? Colors.black : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () {
                                if (useMasterPin) {
                                  Navigator.pop(dialogCtx, masterPin);
                                  return;
                                }
                                final p = passCtrl.text.trim();
                                if (p.isEmpty) {
                                  setDialogState(() => errorMsg = 'Please enter a password');
                                  return;
                                }
                                if (isExport) {
                                  if (p.length < 4) {
                                    setDialogState(() => errorMsg = 'Password must be at least 4 characters');
                                    return;
                                  }
                                  if (p != confirmCtrl.text.trim()) {
                                    setDialogState(() => errorMsg = 'Passwords do not match!');
                                    return;
                                  }
                                }
                                Navigator.pop(dialogCtx, p);
                              },
                              child: Text(isExport ? 'Export' : 'Unlock', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _promptPinInput(BuildContext context, {required String title, required String subtitle}) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        String input = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ('●' * input.length).padRight(4, '○'),
                    style: TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                    children: List.generate(12, (i) {
                      if (i == 9) {
                        return const SizedBox(width: 64, height: 64);
                      }
                      if (i == 11) {
                        return GestureDetector(
                          onTap: () {
                            if (input.isNotEmpty) {
                              setDialogState(() {
                                input = input.substring(0, input.length - 1);
                              });
                            }
                          },
                          child: Container(
                            width: 64, height: 64,
                            alignment: Alignment.center,
                            child: const Icon(Icons.backspace_outlined, size: 22),
                          ),
                        );
                      }
                      final n = i == 10 ? 0 : i + 1;
                      return GestureDetector(
                        onTap: () {
                          if (input.length < 4) {
                            setDialogState(() {
                              input += n.toString();
                            });
                            if (input.length == 4) {
                              Navigator.pop(dialogCtx, input);
                            }
                          }
                        },
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                          alignment: Alignment.center,
                          child: Text(n.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportEncryptedFile() async {
    final masterPin = await storage.read(key: 'master_pin');
    if (!mounted) return;

    final enteredPin = await _promptPinInput(
      context,
      title: 'Verify Master PIN',
      subtitle: 'Enter your Master PIN to authorize export.',
    );

    if (enteredPin == null) return;

    if (enteredPin != masterPin) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ Incorrect Master PIN. Export aborted!'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final filePassword = await _promptPasswordDialog(
      context,
      title: 'Lock Backup File',
      subtitle: 'Set a strong password for this file, or select your Master PIN.',
      isExport: true,
      masterPin: masterPin,
    );

    if (filePassword == null) return;

    final dataStr = await storage.read(key: 'vault_data');
    final cardPin = await storage.read(key: 'card_pin');
    final passPin = await storage.read(key: 'pass_pin');

    List<dynamic> items = [];
    if (dataStr != null && dataStr.isNotEmpty) {
      try {
        items = jsonDecode(dataStr);
      } catch (_) {}
    }

    final backupPayload = {
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'vault_data': items,
      'master_pin': masterPin,
      'card_pin': cardPin,
      'pass_pin': passPin,
    };

    final plainJson = jsonEncode(backupPayload);
    final encryptedEnvelope = VaultCrypto.encrypt(plainText: plainJson, password: filePassword);

    final fileName = 'vault_backup_${DateTime.now().millisecondsSinceEpoch}.enc';

    try {
      if (kIsWeb) {
        final bytes = utf8.encode(encryptedEnvelope);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(Uint8List.fromList(bytes), name: fileName, mimeType: 'application/octet-stream')],
            title: 'Secure Vault Backup',
            subject: 'Secure Vault Encrypted Backup',
          ),
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(encryptedEnvelope);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/octet-stream', name: fileName)],
            title: 'Secure Vault Backup',
            subject: 'Secure Vault Encrypted Backup',
          ),
        );
      }

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Encrypted file ready! Protected with AES-256.', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: isDark ? Colors.white : Colors.black,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _importEncryptedFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (files.isEmpty) return;
      final file = files.first;

      final String fileContent = await file.xFile.readAsString();

      if (!fileContent.contains('SecureVault')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid file! Not a Secure Vault encrypted file.'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      if (!mounted) return;

      final enteredPassword = await _promptPasswordDialog(
        context,
        title: 'Unlock Document',
        subtitle: 'Enter the password or Master PIN that was used to encrypt this file.',
        isExport: false,
      );

      if (enteredPassword == null) return;

      final decryptedJson = VaultCrypto.decrypt(encryptedJson: fileContent, password: enteredPassword);

      if (decryptedJson == null) {
        if (mounted) {
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Incorrect Password! Decryption failed. Cannot open document.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
        return;
      }

      final Map<String, dynamic> backupData = jsonDecode(decryptedJson);
      final List<dynamic> itemsToRestore = backupData['vault_data'] ?? [];
      final String? masterPin = backupData['master_pin']?.toString();
      final String? cardPin = backupData['card_pin']?.toString();
      final String? passPin = backupData['pass_pin']?.toString();

      final cardsCount = itemsToRestore.where((i) => i['isCard'] == true).length;
      final passesCount = itemsToRestore.where((i) => i['isCard'] != true).length;

      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      final shouldRestore = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetCtx) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.lock_open_rounded, color: Colors.green, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Document Decrypted & Verified!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          const SizedBox(height: 4),
                          Text('$cardsCount Cards, $passesCount Passwords unlocked', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'The file has been decrypted using your Master PIN. Restore all items into your vault on this device?',
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        child: Text('Close', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(sheetCtx, true),
                        child: const Text('Restore All', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );

      if (shouldRestore == true) {
        await storage.write(key: 'vault_data', value: jsonEncode(itemsToRestore));
        if (masterPin != null && masterPin.isNotEmpty) {
          await storage.write(key: 'master_pin', value: masterPin);
        }
        if (cardPin != null && cardPin.isNotEmpty) {
          await storage.write(key: 'card_pin', value: cardPin);
        }
        if (passPin != null && passPin.isNotEmpty) {
          await storage.write(key: 'pass_pin', value: passPin);
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasOnboarded', true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Restored $cardsCount cards and $passesCount passwords to this device!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _connectGoogleDrive() async {
    String? webEmail;
    if (kIsWeb) {
      final emailCtrl = TextEditingController(text: _googleEmail ?? '');
      final isDark = Theme.of(context).brightness == Brightness.dark;
      webEmail = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.add_to_drive_rounded, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text('Google Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter your Google Account email to sync your encrypted vault:', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '',
                  prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  filled: true,
                  fillColor: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.08),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : Colors.black,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
              child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (webEmail == null || webEmail.isEmpty) return;
    }

    setState(() => _isGoogleDriveBusy = true);
    try {
      final email = await GoogleDriveService.instance.signIn(promptEmailOnWeb: webEmail);
      if (email != null) {
        final lastSync = await GoogleDriveService.instance.getLastSyncFormatted();
        if (mounted) {
          setState(() {
            _googleEmail = email;
            _lastSyncText = lastSync;
            _isGoogleDriveBusy = false;
          });

          showLuxuryNotification(
            context,
            title: 'Google Drive Connected',
            message: 'Signed in as $email',
            icon: Icons.cloud_done_rounded,
          );
        }

        // Check if a backup exists in Google Drive
        final backupInfo = await GoogleDriveService.instance.checkBackupInfo();
        if (backupInfo != null && mounted) {
          final shouldRestore = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
              return AlertDialog(
                backgroundColor: isDark ? AppColors.darkCard : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: const Row(
                  children: [
                    Icon(Icons.cloud_done_rounded, color: Colors.blueAccent),
                    SizedBox(width: 10),
                    Expanded(child: Text('Cloud Backup Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  ],
                ),
                content: const Text(
                  'We found an existing Aegis vault backup in your Google Drive. Would you like to restore your cards and credentials now?',
                  style: TextStyle(fontSize: 14),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Not Now', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Restore Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          );

          if (shouldRestore == true && mounted) {
            await _restoreFromGoogleDrive();
          }
        }
      } else {
        if (mounted) setState(() => _isGoogleDriveBusy = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleDriveBusy = false);
        final isError10 = e.toString().contains('10') || e.toString().contains('sign_in_failed');
        if (isError10) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? AppColors.darkCard : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Expanded(child: Text('Google Sign-In Setup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Error 10 (DEVELOPER_ERROR): Google Play Services requires your app\'s SHA-1 certificate fingerprint to be added in Google Cloud Console / Firebase Console.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  const Text('Package: com.example.myfirstapp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  const SelectableText(
                    'SHA-1: A7:13:61:A2:9C:CF:7C:12:30:13:E3:99:E1:B4:7E:EC:2A:4B:7A:9E',
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.blueAccent, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Would you like to copy the SHA-1 or sync with your email address directly?',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: 'A7:13:61:A2:9C:CF:7C:12:30:13:E3:99:E1:B4:7E:EC:2A:4B:7A:9E'));
                    Navigator.pop(ctx);
                    showLuxuryNotification(context, title: 'SHA-1 Copied', message: 'Certificate fingerprint copied to clipboard');
                  },
                  child: const Text('Copy SHA-1'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : Colors.black,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _promptEmailSyncFallback();
                  },
                  child: const Text('Sync with Email', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        } else {
          showLuxuryNotification(
            context,
            title: 'Google Sign-In Error',
            message: '$e',
            isError: true,
          );
        }
      }
    }
  }

  Future<void> _promptEmailSyncFallback() async {
    final emailCtrl = TextEditingController(text: _googleEmail ?? '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enteredEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Connect with Email', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your Google Account email to enable zero-knowledge encrypted sync:', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'name@gmail.com',
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
                filled: true,
                fillColor: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
            child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (enteredEmail == null || enteredEmail.isEmpty) return;

    setState(() => _isGoogleDriveBusy = true);
    final email = await GoogleDriveService.instance.signIn(promptEmailOnWeb: enteredEmail);
    if (email != null && mounted) {
      final lastSync = await GoogleDriveService.instance.getLastSyncFormatted();
      setState(() {
        _googleEmail = email;
        _lastSyncText = lastSync;
        _isGoogleDriveBusy = false;
      });
      showLuxuryNotification(
        context,
        title: 'Google Drive Connected',
        message: 'Cloud sync enabled for $email',
        icon: Icons.cloud_done_rounded,
      );
    } else {
      if (mounted) setState(() => _isGoogleDriveBusy = false);
    }
  }

  Future<void> _syncToGoogleDrive() async {
    final masterPin = await storage.read(key: 'master_pin');
    if (masterPin == null || masterPin.isEmpty) {
      if (mounted) {
        showLuxuryNotification(
          context,
          title: 'Master PIN Required',
          message: 'Please set up a Master PIN first before syncing.',
          isError: true,
        );
      }
      return;
    }

    setState(() => _isGoogleDriveBusy = true);
    try {
      final dataStr = await storage.read(key: 'vault_data');
      final cardPin = await storage.read(key: 'card_pin');
      final passPin = await storage.read(key: 'pass_pin');

      List<dynamic> items = [];
      if (dataStr != null && dataStr.isNotEmpty) {
        try {
          items = jsonDecode(dataStr);
        } catch (_) {}
      }

      final backupPayload = {
        'version': 2,
        'exported_at': DateTime.now().toIso8601String(),
        'vault_data': items,
        'master_pin': masterPin,
        'card_pin': cardPin,
        'pass_pin': passPin,
      };

      final plainJson = jsonEncode(backupPayload);
      final encryptedEnvelope = VaultCrypto.encrypt(plainText: plainJson, password: masterPin);

      await GoogleDriveService.instance.uploadEncryptedVault(encryptedEnvelope);
      final lastSync = await GoogleDriveService.instance.getLastSyncFormatted();

      if (mounted) {
        setState(() {
          _lastSyncText = lastSync;
          _isGoogleDriveBusy = false;
        });
        HapticFeedback.lightImpact();
        showLuxuryNotification(
          context,
          title: 'Vault Synced',
          message: 'Encrypted and backed up to Google Drive.',
          icon: Icons.cloud_done_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleDriveBusy = false);
        final cleanMsg = e.toString().replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
        showLuxuryNotification(
          context,
          title: 'Sync Failed',
          message: cleanMsg.length > 80 ? 'Unable to reach Google Drive. Please check your connection.' : cleanMsg,
          isError: true,
        );
      }
    }
  }

  Future<void> _restoreFromGoogleDrive() async {
    setState(() => _isGoogleDriveBusy = true);
    try {
      final encryptedContent = await GoogleDriveService.instance.downloadEncryptedVault();
      if (mounted) setState(() => _isGoogleDriveBusy = false);

      if (encryptedContent == null) {
        if (mounted) {
          showLuxuryNotification(
            context,
            title: 'No Cloud Backup Found',
            message: 'No backup file found in this Google Drive account. Sync first to create one.',
            isError: true,
            icon: Icons.cloud_off_rounded,
          );
        }
        return;
      }

      if (!mounted) return;

      final enteredPassword = await _promptPasswordDialog(
        context,
        title: 'Restore from Google Drive',
        subtitle: 'Enter your Master PIN to decrypt and restore your vault items.',
        isExport: false,
      );

      if (enteredPassword == null) return;

      final decryptedJson = VaultCrypto.decrypt(encryptedJson: encryptedContent, password: enteredPassword);
      if (decryptedJson == null) {
        if (mounted) {
          HapticFeedback.heavyImpact();
          showLuxuryNotification(
            context,
            title: 'Incorrect Master PIN',
            message: 'Decryption failed. Cannot restore backup.',
            isError: true,
          );
        }
        return;
      }

      final Map<String, dynamic> backupData = jsonDecode(decryptedJson);
      final List<dynamic> itemsToRestore = backupData['vault_data'] ?? [];
      final String? masterPin = backupData['master_pin']?.toString();
      final String? cardPin = backupData['card_pin']?.toString();
      final String? passPin = backupData['pass_pin']?.toString();

      final cardsCount = itemsToRestore.where((i) => i['isCard'] == true).length;
      final passesCount = itemsToRestore.where((i) => i['isCard'] != true).length;

      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;

      final shouldRestore = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetCtx) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cloud Backup Decrypted!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          const SizedBox(height: 4),
                          Text('$cardsCount Cards, $passesCount Credentials unlocked', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Restore all $cardsCount cards and $passesCount credentials from Google Drive to this device?',
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(sheetCtx, true),
                        child: const Text('Restore All', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );

      if (shouldRestore == true) {
        await storage.write(key: 'vault_data', value: jsonEncode(itemsToRestore));
        if (masterPin != null && masterPin.isNotEmpty) {
          await storage.write(key: 'master_pin', value: masterPin);
        }
        if (cardPin != null && cardPin.isNotEmpty) {
          await storage.write(key: 'card_pin', value: cardPin);
        }
        if (passPin != null && passPin.isNotEmpty) {
          await storage.write(key: 'pass_pin', value: passPin);
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasOnboarded', true);

        if (mounted) {
          showLuxuryNotification(
            context,
            title: 'Vault Restored Successfully',
            message: 'Restored $cardsCount cards and $passesCount credentials from Google Drive.',
            icon: Icons.cloud_download_rounded,
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleDriveBusy = false);
        final cleanMsg = e.toString().replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
        showLuxuryNotification(
          context,
          title: 'Restore Failed',
          message: cleanMsg.length > 80 ? 'Unable to restore vault. Please check connection and try again.' : cleanMsg,
          isError: true,
        );
      }
    }
  }

  Future<void> _disconnectGoogleDrive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Disconnect Google Drive?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Your local cards and credentials will remain completely safe on this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await GoogleDriveService.instance.signOut();
      if (mounted) {
        setState(() {
          _googleEmail = null;
          _lastSyncText = null;
        });
        showLuxuryNotification(
          context,
          title: 'Google Drive Disconnected',
          message: 'Local cards and data remain safe on this device.',
          icon: Icons.link_off_rounded,
        );
      }
    }
  }

  Widget _buildGoogleDriveCard(BuildContext context, bool isDark) {
    final isConnected = _googleEmail != null && _googleEmail!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F4F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_to_drive_rounded, color: Colors.blueAccent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Google Drive Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      isConnected ? 'Auto-sync active' : 'Zero-knowledge encrypted cloud backup',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.greenAccent.withValues(alpha: 0.15)
                      : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Connected' : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isConnected) ...[
            Text(
              'Link your Google account to auto-sync your cards & credentials. When you switch devices or reinstall, select your email to restore your entire vault.',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _isGoogleDriveBusy ? null : _connectGoogleDrive,
                icon: _isGoogleDriveBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                    : const Icon(Icons.cloud_sync_rounded, size: 20),
                label: Text(
                  _isGoogleDriveBusy ? 'Connecting...' : 'Connect Google Account',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                    child: Text(
                      _googleEmail!.isNotEmpty ? _googleEmail![0].toUpperCase() : 'G',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_googleEmail!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          _lastSyncText != null ? 'Last synced: $_lastSyncText' : 'Never synced yet',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sync Now',
                    onPressed: _isGoogleDriveBusy ? null : _syncToGoogleDrive,
                    icon: _isGoogleDriveBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 22),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _disconnectGoogleDrive,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
                child: const Text('Disconnect Account', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = SecureVaultApp.of(context);
    final isCurrentlyDark = themeController.value == ThemeMode.dark;

    return ListView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 120),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
        const SizedBox(height: 32),
        _buildSectionHeader(context, 'Security'),
        _buildSettingsTile(
          context,
          title: 'Change Master PIN',
          subtitle: 'Update your 4-digit master PIN',
          icon: Icons.pin,
          onTap: _changePin,
        ),
        _buildSettingsTile(
          context,
          title: 'Change Card PIN',
          subtitle: 'Update 4-digit PIN to unlock cards',
          icon: Icons.credit_card,
          onTap: _changeCardPin,
        ),
        _buildSettingsTile(
          context,
          title: 'Change Password PIN',
          subtitle: 'Update 4-digit PIN to unlock passwords',
          icon: Icons.key_rounded,
          onTap: _changePasswordPin,
        ),
        _buildSettingsSwitch(
          context,
          title: 'Biometric Unlock',
          subtitle: 'Use FaceID / Fingerprint to unlock',
          icon: Icons.fingerprint,
          value: _useBiometrics,
          onChanged: (val) async {
            setState(() => _useBiometrics = val);
            await storage.write(key: 'use_biometrics', value: val.toString());
          },
        ),
        _buildSettingsTile(
          context,
          title: 'Auto-Lock Timeout',
          subtitle: _autoLock,
          icon: Icons.timer,
          onTap: _changeAutoLock,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Appearance'),
        _buildSettingsSwitch(
          context,
          title: 'Dark Mode',
          subtitle: 'Experience the sleek dark theme',
          icon: Icons.dark_mode,
          value: isCurrentlyDark,
          onChanged: (_) => themeController.toggle(),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Data & Cloud (Encrypted)'),
        _buildGoogleDriveCard(context, isCurrentlyDark),
        _buildSettingsTile(
          context,
          title: 'Export Encrypted Backup',
          subtitle: 'Download AES-256 encrypted file protected with Master PIN',
          icon: Icons.shield_outlined,
          onTap: _exportEncryptedFile,
        ),
        _buildSettingsTile(
          context,
          title: 'Import Backup',
          subtitle: 'Pick .enc file and enter Master PIN to decrypt & restore',
          icon: Icons.lock_open_rounded,
          onTap: _importEncryptedFile,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'About & Updates'),
        _buildSettingsTile(
          context,
          title: 'Check for Updates',
          subtitle: 'Aegis Vault v1.0.0',
          icon: Icons.system_update_rounded,
          trailing: _isCheckingUpdates
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _isCheckingUpdates
              ? null
              : () async {
                  setState(() => _isCheckingUpdates = true);
                  await AppUpdateService.instance.checkForUpdate(
                    context,
                    silent: false,
                    onUpToDate: () {
                      if (mounted) {
                        showLuxuryNotification(
                          context,
                          title: 'Aegis is Up to Date',
                          message: 'You have the latest version installed.',
                          icon: Icons.check_circle_rounded,
                        );
                      }
                    },
                    onError: (err) {
                      if (mounted) {
                        showLuxuryNotification(
                          context,
                          title: 'Update Check Failed',
                          message: err,
                          isError: true,
                        );
                      }
                    },
                  );
                  if (mounted) {
                    setState(() => _isCheckingUpdates = false);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }

  Widget _buildSettingsTile(BuildContext context, {required String title, required String subtitle, required IconData icon, Widget? trailing, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: isDark ? AppColors.darkCard : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isDark ? Colors.black : Colors.grey[100], shape: BoxShape.circle), child: Icon(icon, color: isDark ? Colors.white : Colors.black)),
          trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildSettingsSwitch(BuildContext context, {required String title, required String subtitle, required IconData icon, required bool value, required ValueChanged<bool> onChanged}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: isDark ? AppColors.darkCard : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          secondary: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isDark ? Colors.black : Colors.grey[100], shape: BoxShape.circle), child: Icon(icon, color: isDark ? Colors.white : Colors.black)),
          value: value,
          activeThumbColor: isDark ? Colors.white : Colors.black,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }
}

class VaultItemTile extends StatelessWidget {
  final SecretItem item;
  final VoidCallback onTap;
  const VaultItemTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (item.isCard) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onTap: onTap,
          child: Hero(
            tag: 'hero-${item.id}',
            child: Material(
              color: Colors.transparent,
              child: UniversalCardWidget(
                bankName: item.title,
                cardType: item.cardType,
                secret: item.secret,
                cardholderName: item.username,
                expiryDate: item.expiryDate,
                cardProvider: item.cardProvider,
                isMasked: true,
              ),
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black : Colors.grey[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock, color: isDark ? Colors.white : Colors.black, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(item.username, style: const TextStyle(color: Colors.grey, fontSize: 14), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined, color: isDark ? Colors.white70 : Colors.black54, size: 18),
                      const SizedBox(width: 4),
                      Text('View', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CardExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (oldValue.text.length > newValue.text.length) {
      if (oldValue.text.length == 3 && oldValue.text.endsWith('/')) {
        final text = newValue.text.replaceAll('/', '');
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      return newValue;
    }

    var clean = newValue.text.replaceAll('/', '');
    if (clean.length > 4) {
      clean = clean.substring(0, 4);
    }

    String formatted = clean;
    if (clean.length >= 2) {
      formatted = '${clean.substring(0, 2)}/${clean.substring(2)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// --- Add / Edit Screen ---
class AddEditItemPage extends StatefulWidget {
  final SecretItem? existingItem;
  const AddEditItemPage({super.key, this.existingItem});
  @override
  State<AddEditItemPage> createState() => _AddEditItemPageState();
}

class _AddEditItemPageState extends State<AddEditItemPage> {
  final _formKey = GlobalKey<FormState>();
  late bool _isCard;
  
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _secretCtrl = TextEditingController();
  final TextEditingController _cvvCtrl = TextEditingController();
  final TextEditingController _expiryCtrl = TextEditingController();
  
  late String _category;
  late String _cardType;
  late String _cardProvider;

  @override
  void initState() {
    super.initState();
    isCurrentlyEditing = true;
    final e = widget.existingItem;
    _isCard = e?.isCard ?? true;
    _titleCtrl.text = e?.title ?? '';
    _usernameCtrl.text = e?.username ?? '';
    _secretCtrl.text = e?.secret ?? '';
    _cvvCtrl.text = e?.cvv ?? '';
    _expiryCtrl.text = e?.expiryDate ?? '';
    _category = e?.category ?? 'Other';
    _cardType = e?.cardType ?? 'Debit';
    _cardProvider = e?.cardProvider ?? 'Mastercard';
  }

  Future<void> _deleteItem() async {
    final storage = const FlutterSecureStorage();
    final dataStr = await storage.read(key: 'vault_data');
    if (dataStr != null) {
      List<dynamic> items = jsonDecode(dataStr);
      items.removeWhere((i) => i['id'] == widget.existingItem!.id);
      await storage.write(key: 'vault_data', value: jsonEncode(items));
      unawaited(GoogleDriveService.instance.triggerAutoSyncIfEnabled());
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      final newItem = SecretItem(
        id: widget.existingItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleCtrl.text.isEmpty ? (_isCard ? 'MY CARD' : 'New Secret') : (_isCard ? _titleCtrl.text.toUpperCase() : _titleCtrl.text),
        username: _isCard ? _usernameCtrl.text.toUpperCase() : _usernameCtrl.text,
        secret: _secretCtrl.text,
        isCard: _isCard,
        category: _category,
        cardType: _cardType,
        cvv: _cvvCtrl.text,
        cardProvider: _cardProvider,
        expiryDate: _expiryCtrl.text,
      );
      
      final storage = const FlutterSecureStorage();
      final dataStr = await storage.read(key: 'vault_data');
      List<dynamic> items = dataStr != null ? jsonDecode(dataStr) : [];
      
      if (widget.existingItem != null) {
        final index = items.indexWhere((i) => i['id'] == widget.existingItem!.id);
        if (index >= 0) items[index] = newItem.toMap();
      } else {
        items.add(newItem.toMap());
      }
      
      await storage.write(key: 'vault_data', value: jsonEncode(items));
      unawaited(GoogleDriveService.instance.triggerAutoSyncIfEnabled());
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF131314) : const Color(0xFFEFEFEF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              decoration: BoxDecoration(color: isDark ? AppColors.darkCard : Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.chevron_left, color: isDark ? Colors.white : Colors.black),
            ),
          ),
        ),
        title: Text(widget.existingItem == null ? (_isCard ? 'Add Card' : 'Add Secret') : 'Edit Item', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (widget.existingItem != null)
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), onPressed: _deleteItem)
          else
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: isDark ? AppColors.darkCard : Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.history, color: Colors.grey, size: 20),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.existingItem == null)
                Container(
                  margin: const EdgeInsets.only(bottom: 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isCard = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isCard ? (isDark ? Colors.white : Colors.black) : (isDark ? AppColors.darkCard : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Card', 
                              style: TextStyle(
                                color: _isCard ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6)), 
                                fontWeight: FontWeight.bold
                              )
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isCard = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isCard ? (isDark ? Colors.white : Colors.black) : (isDark ? AppColors.darkCard : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Credential', 
                              style: TextStyle(
                                color: !_isCard ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.6)), 
                                fontWeight: FontWeight.bold
                              )
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              if (_isCard) _buildLiveCardPreview(isDark),
              if (_isCard) const SizedBox(height: 32),

              _buildInputGroup(
                isDark,
                label: _isCard ? 'Bank Name' : 'Title',
                controller: _titleCtrl,
                hint: _isCard ? 'STATE BANK OF INDIA' : 'Netflix',
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              if (_isCard) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Card Provider', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _cardProvider,
                            items: const [
                              DropdownMenuItem(value: 'Auto', child: Text('Auto')),
                              DropdownMenuItem(value: 'Visa', child: Text('Visa')),
                              DropdownMenuItem(value: 'Mastercard', child: Text('Mastercard')),
                              DropdownMenuItem(value: 'RuPay', child: Text('RuPay')),
                            ],
                            onChanged: (v) => setState(() => _cardProvider = v!),
                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: isDark ? Colors.white : Colors.black),
                            dropdownColor: isDark ? AppColors.darkCard : Colors.white,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDark ? AppColors.darkCard : Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Card Type', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _cardType,
                            items: const [
                              DropdownMenuItem(value: 'Debit', child: Text('Debit')),
                              DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                            ],
                            onChanged: (v) => setState(() => _cardType = v!),
                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: isDark ? Colors.white : Colors.black),
                            dropdownColor: isDark ? AppColors.darkCard : Colors.white,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: isDark ? AppColors.darkCard : Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              _buildInputGroup(
                isDark,
                label: _isCard ? 'Cardholder Name' : 'Username / Email',
                controller: _usernameCtrl,
                hint: _isCard ? 'John Doe' : 'user@example.com',
                textCapitalization: _isCard ? TextCapitalization.characters : TextCapitalization.none,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              _buildInputGroup(
                isDark,
                label: _isCard ? 'Card Number' : 'Password',
                controller: _secretCtrl,
                hint: _isCard ? '0123456789' : '••••••••',
                keyboardType: _isCard ? TextInputType.number : TextInputType.text,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),

              if (_isCard)
                Row(
                  children: [
                    Expanded(
                      child: _buildInputGroup(
                        isDark,
                        label: 'Expires',
                        controller: _expiryCtrl,
                        hint: '10/28',
                        keyboardType: TextInputType.datetime,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                          CardExpiryInputFormatter(),
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInputGroup(
                        isDark,
                        label: 'CVV',
                        controller: _cvvCtrl,
                        hint: '***',
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: isDark ? Colors.white : Colors.black,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                ),
                onPressed: _saveItem,
                child: const Text('Add & Continue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputGroup(
    bool isDark, {
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3)),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white : Colors.black, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveCardPreview(bool isDark) {
    return UniversalCardWidget(
      bankName: _titleCtrl.text,
      cardType: _cardType,
      secret: _secretCtrl.text,
      cardholderName: _usernameCtrl.text,
      expiryDate: _expiryCtrl.text,
      cardProvider: _cardProvider,
    );
  }

  @override
  void dispose() {
    isCurrentlyEditing = false;
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _secretCtrl.dispose();
    _cvvCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _export(BuildContext context) async {
    final storage = const FlutterSecureStorage();
    final dataStr = await storage.read(key: 'vault_data');
    if (dataStr != null) {
      Clipboard.setData(ClipboardData(text: dataStr));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vault data exported to clipboard (Encrypted JSON)')));
      }
    }
  }

  void _import(BuildContext context) async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      try {
        final decoded = jsonDecode(data.text!);
        if (decoded is List) {
          final storage = const FlutterSecureStorage();
          await storage.write(key: 'vault_data', value: data.text);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vault data imported successfully! Restart app.')));
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Vault Data')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = SecureVaultApp.of(context).value;
    final isDark = themeMode == ThemeMode.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SwitchListTile(
            title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold)),
            value: isDark,
            activeColor: isDark ? Colors.white : Colors.black,
            onChanged: (val) => SecureVaultApp.of(context).toggle(),
            secondary: const Icon(Icons.dark_mode),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Change Master PIN', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context, FadeScaleRoute(page: const PinSetupScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export Vault (to Clipboard)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Save your encrypted JSON locally'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import Vault (from Clipboard)', style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => _import(context),
          ),
        ],
      ),
    );
  }
}

// --- View Item Screen ---
class ViewItemScreen extends StatefulWidget {
  final SecretItem item;
  const ViewItemScreen({super.key, required this.item});

  @override
  State<ViewItemScreen> createState() => _ViewItemScreenState();
}

class _ViewItemScreenState extends State<ViewItemScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isFront = true;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _animation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _autoCloseTimer = Timer(const Duration(minutes: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _flipCard() {
    if (_isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _isFront = !_isFront;
  }

  Widget _buildFront(Color bgColor, Color textColor, bool isDark) {
    if (widget.item.isCard) {
      return UniversalCardWidget(
        bankName: widget.item.title,
        cardType: widget.item.cardType,
        secret: widget.item.secret,
        cardholderName: widget.item.username,
        expiryDate: widget.item.expiryDate,
        cardProvider: widget.item.cardProvider,
        isMasked: false,
      );
    }
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(widget.item.title, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold))),
                Icon(Icons.lock, color: textColor),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Password & Secret', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 24),
            Text(widget.item.secret, style: TextStyle(color: textColor, fontSize: 22, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('USERNAME / ACCOUNT', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(widget.item.username, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBack(Color bgColor, Color textColor, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24)),
        child: Stack(
          children: [
            if (widget.item.isCard) Positioned.fill(child: CardPattern(isDark: isDark)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(height: 38, color: Colors.black),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(child: Container(height: 36, color: Colors.grey[300])),
                            Container(
                              height: 36, width: 60, color: Colors.white, alignment: Alignment.center,
                              child: Text(widget.item.cvv, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                            )
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text('This card is securely stored in Vault.', style: TextStyle(color: Colors.black.withValues(alpha: 0.5), fontSize: 10)),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCard = widget.item.isCard;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? AppColors.darkCard : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final result = await Navigator.push(context, FadeScaleRoute(page: AddEditItemPage(existingItem: widget.item)));
              if (result == true) {
                if (!mounted) return;
                Navigator.pop(context, true);
              }
            },
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: isCard ? _flipCard : null,
                child: isCard
                    ? Hero(
                        tag: 'hero-${widget.item.id}',
                        flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                          return SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: toHeroContext.widget,
                          );
                        },
                        child: Material(
                          color: Colors.transparent,
                          child: AnimatedBuilder(
                            animation: _animation,
                            builder: (context, child) {
                              final angle = _animation.value * pi;
                              final isBack = angle > pi / 2;
                              return Transform(
                                transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
                                alignment: Alignment.center,
                                child: isBack
                                    ? Transform(
                                        transform: Matrix4.identity()..rotateY(pi),
                                        alignment: Alignment.center,
                                        child: _buildBack(bgColor, textColor, isDark),
                                      )
                                    : _buildFront(bgColor, textColor, isDark),
                              );
                            },
                          ),
                        ),
                      )
                    : _buildFront(bgColor, textColor, isDark),
              ),
              const SizedBox(height: 32),
              if (isCard)
                const Text('Tap the card to flip and view CVV', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.item.secret));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied Number!')));
                    },
                    icon: const Icon(Icons.copy), label: Text(isCard ? 'Copy Number' : 'Copy Password', style: const TextStyle(color: Colors.grey))
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.item.username));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied Name!')));
                    },
                    icon: const Icon(Icons.copy), label: const Text('Copy Name', style: TextStyle(color: Colors.grey))
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class CardPattern extends StatelessWidget {
  final bool isDark;
  const CardPattern({super.key, this.isDark = true});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE8B79B), Color(0xFF67C7A8)],
              ),
            ),
          ),
          Positioned(
            right: -50, top: -50,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                gradient: RadialGradient(
                  colors: [Colors.white.withOpacity(0.15), Colors.transparent],
                  stops: const [0.0, 1.0]
                )
              ),
            ),
          ),
          Positioned(
            left: -80, bottom: -40,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                gradient: RadialGradient(
                  colors: [isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05), Colors.transparent],
                  stops: const [0.0, 1.0]
                )
              ),
            ),
          ),
          Positioned(
            right: 40, bottom: -60,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                gradient: RadialGradient(
                  colors: [Colors.white.withOpacity(0.05), Colors.transparent],
                  stops: const [0.0, 1.0]
                )
              ),
            ),
          ),
          // Subtle noise/glass layer
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.white.withOpacity(0.02)),
            ),
          )
        ],
      ),
    );
  }
}

Widget getCardLogo(SecretItem item) {
  if (item.secret.isEmpty) return const SizedBox();
  
  String detected = 'Auto';
  if (item.cardProvider == 'Auto') {
    final String normalized = item.secret.replaceAll(' ', '');
    if (normalized.startsWith('4')) {
      detected = 'Visa';
    } else if (normalized.startsWith('5') || normalized.startsWith('2')) {
      detected = 'Mastercard';
    } else if (normalized.startsWith('6')) {
      detected = 'RuPay';
    }
  } else {
    detected = item.cardProvider;
  }

  if (detected == 'Visa') {
    return const Text('VISA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, fontStyle: FontStyle.italic));
  } else if (detected == 'Mastercard') {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), shape: BoxShape.circle)),
        Transform.translate(offset: const Offset(-10, 0), child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), shape: BoxShape.circle))),
      ],
    );
  } else if (detected == 'RuPay') {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Ru', style: TextStyle(color: Color(0xFFE35205), fontWeight: FontWeight.w900, fontSize: 20, fontStyle: FontStyle.italic)),
        Text('Pay', style: TextStyle(color: Color(0xFF1A1F71), fontWeight: FontWeight.w900, fontSize: 20, fontStyle: FontStyle.italic)),
      ],
    );
  }
  return const SizedBox();
}

class EmptyVaultState extends StatelessWidget {
  final bool isDark;
  final bool isCardsView;
  final VoidCallback onAdd;

  const EmptyVaultState({super.key, required this.isDark, required this.isCardsView, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 36),
          Icon(
            isCardsView ? Icons.credit_card_off_rounded : Icons.lock_outline_rounded,
            size: 86,
            color: isDark ? Colors.white.withValues(alpha: 0.28) : Colors.black.withValues(alpha: 0.24),
          ),
          const SizedBox(height: 28),
          Text(isCardsView ? 'No Cards Found' : 'Your Vault is Empty', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 12),
          Text(
            isCardsView ? 'Securely store your credit and debit cards here.' : 'Add your first password or secure note.',
            style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onAdd();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text('Add New Secret', style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }
}

class FadeScaleRoute extends PageRouteBuilder {
  final Widget page;
  FadeScaleRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
}

