import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

old_tile = """class VaultItemTile extends StatelessWidget {
  final SecretItem item;
  final VoidCallback onTap;
  const VaultItemTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isCard = item.isCard;
    final Color bgColor = isCard ? AppColors.walletBlueDark : AppColors.walletBlue;
    final Color textColor = Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'hero-${item.id}',
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(24)),
            child: Stack(
              children: [
                if (isCard) Positioned.fill(child: CardPattern(isDark: Theme.of(context).brightness == Brightness.dark)),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(item.title, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold))),
                          if (isCard) getCardLogo(item) else Icon(Icons.lock, color: textColor),
                        ],
                      ),
                      if (isCard) ...[
                        const SizedBox(height: 8),
                        Text(item.cardType, style: TextStyle(color: textColor.withOpacity(0.7), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.username, style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 14), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(_formatCard(item.secret), style: TextStyle(color: textColor, fontSize: 18, letterSpacing: 2, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                              child: const Row(
                                children: [
                                  Icon(Icons.visibility, color: Colors.white, size: 16),
                                  SizedBox(width: 8),
                                  Text('View', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )
                          ],
                        )
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(item.username, style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 16), overflow: TextOverflow.ellipsis),
                      ]
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

  String _formatCard(String s) {
    if (s.length < 4) return s;
    return '•••• •••• •••• ${s.substring(s.length - 4)}';
  }
}"""

new_tile = """class VaultItemTile extends StatelessWidget {
  final SecretItem item;
  final VoidCallback onTap;
  const VaultItemTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? AppColors.darkCard : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'hero-${item.id}',
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bgColor, 
              borderRadius: BorderRadius.circular(20),
              boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.walletBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: AppColors.walletBlue),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(item.username, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}"""

content = content.replace(old_tile, new_tile)

with open('lib/main.dart', 'w') as f:
    f.write(content)
