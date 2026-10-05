import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

start_str = "class OnboardingScreen extends StatefulWidget {"
end_str = "class MainTabScreen extends StatefulWidget {"

if start_str in content and end_str in content:
    start_idx = content.find(start_str)
    end_idx = content.find(end_str)
    
    new_code = """class OnboardingScreen extends StatefulWidget {
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
                AppColors.walletBlue
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
                    decoration: BoxDecoration(color: _currentPage == index ? AppColors.walletBlue : Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(4)),
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
                    decoration: BoxDecoration(color: AppColors.walletBlue, borderRadius: BorderRadius.circular(30)),
                    child: Text(_currentPage == 2 ? 'Get Started' : 'Next', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
                Text(_pin.padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold, color: isDark ? AppColors.walletBlue : Colors.black87)),
                const SizedBox(height: 48),
                _buildKeypad(isDark),
                const SizedBox(height: 48),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _pin.length == 4 ? AppColors.walletBlue : (isDark ? AppColors.darkCard : Colors.grey[200]), foregroundColor: Colors.white, minimumSize: const Size(200, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), elevation: 0),
                  onPressed: _pin.length == 4 ? _savePin : null,
                  child: Text('Confirm PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _pin.length == 4 ? Colors.white : Colors.grey)),
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

// --- PIN Unlock ---
class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key});
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
    Navigator.pushReplacement(context, FadeScaleRoute(page: const MainTabScreen()));
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
                Icon(Icons.lock_rounded, size: 48, color: isDark ? AppColors.walletBlue : Colors.black87),
                const SizedBox(height: 24),
                const Text('Welcome Back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Text(_isError ? 'Incorrect PIN, try again' : 'Enter your Master PIN', style: TextStyle(color: _isError ? Colors.redAccent : Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 40),
                Text(_pin.padRight(4, '○'), style: TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold, color: _isError ? Colors.redAccent : (isDark ? AppColors.walletBlue : Colors.black87))),
                const SizedBox(height: 48),
                _buildKeypad(isDark),
                const SizedBox(height: 32),
                IconButton(
                  icon: const Icon(Icons.fingerprint, size: 36),
                  color: isDark ? AppColors.walletBlue : Colors.black87,
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
"""
    new_content = content[:start_idx] + new_code + content[end_idx:]
    with open('lib/main.dart', 'w') as f:
        f.write(new_content)
    print("Success Onboarding")
else:
    print("Could not find start or end strings")
