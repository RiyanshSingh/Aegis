import sys

with open('lib/main.dart', 'r') as f:
    lines = f.readlines()

new_content = """// --- Home Screen (Google Wallet Style) ---
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
            const Icon(Icons.account_balance_wallet, color: AppColors.walletBlue),
            const SizedBox(width: 12),
            Text('Wallet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 22, color: isDark ? Colors.white : Colors.black)),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () {
              Navigator.push(context, FadeScaleRoute(page: const SettingsScreenWrapper()));
            },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 36, height: 36,
              decoration: const BoxDecoration(color: AppColors.walletBlue, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          )
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const Icon(Icons.contactless_outlined, size: 32, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text('Ready to pay', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                if (cards.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: EmptyVaultState(isDark: isDark, isCardsView: true, onAdd: () async {
                        final result = await Navigator.push(context, FadeScaleRoute(page: const AddEditItemPage()));
                        if (result == true) _loadData();
                      }),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 240,
                      child: PageView.builder(
                        controller: PageController(viewportFraction: 0.85),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: GestureDetector(
                              onTap: () async {
                                final result = await Navigator.push(context, FadeScaleRoute(page: ViewItemScreen(item: cards[index])));
                                if (result == true) _loadData();
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
                      child: Text('Passes & Notes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
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
                            final result = await Navigator.push(context, FadeScaleRoute(page: ViewItemScreen(item: passes[index])));
                            if (result == true) _loadData();
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isDark ? AppColors.walletBlueDark : AppColors.walletBlue,
        foregroundColor: isDark ? Colors.black : Colors.white,
        onPressed: () async {
          final result = await Navigator.push(context, FadeScaleRoute(page: const AddEditItemPage()));
          if (result == true) _loadData();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add to Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildGoogleCard(SecretItem item, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.walletBlue,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CardPattern(isDark: isDark)),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                    getCardLogo(item),
                  ],
                ),
                const SizedBox(height: 8),
                Text(item.cardType, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                const Spacer(),
                Text(_insertSpaces(item.secret), style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _insertSpaces(String text) {
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i + 1) % 4 == 0 && (i + 1) != text.length) buffer.write(' ');
    }
    return buffer.toString();
  }
}

class SettingsScreenWrapper extends StatelessWidget {
  const SettingsScreenWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SettingsView(),
    );
  }
}
"""

lines = lines[:537] + [new_content + '\n'] + lines[825:]

with open('lib/main.dart', 'w') as f:
    f.writelines(lines)
