import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

# I will insert UniversalCardWidget just before class HomeScreen extends StatefulWidget
start_homescreen = "class HomeScreen extends StatefulWidget {"

universal_card_code = """
class UniversalCardWidget extends StatelessWidget {
  final String cardType;
  final String secret;
  final String cardholderName;
  final String expiryDate;
  final String cardProvider;

  const UniversalCardWidget({
    super.key,
    required this.cardType,
    required this.secret,
    required this.cardholderName,
    required this.expiryDate,
    required this.cardProvider,
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

    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFE8B79B), Color(0xFF67C7A8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(cardType, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Icon(Icons.contactless_rounded, color: Colors.white),
                  ],
                ),
                const Spacer(),
                Text(
                  secret.isEmpty ? '8763 2736 9873 0329' : _insertSpaces(secret), 
                  style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700)
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Card Holder Name', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                          Text(cardholderName.isEmpty ? 'Rabbi Rezwan' : cardholderName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Expired Date', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                        Text(expiryDate.isEmpty ? '10/28' : expiryDate, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(width: 24),
                    logo,
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

"""

if start_homescreen in content:
    content = content.replace(start_homescreen, universal_card_code + start_homescreen)
    
    # 1. Replace _buildGoogleCard in HomeScreen with UniversalCardWidget
    # Finding _buildGoogleCard
    old_google_card = """  Widget _buildGoogleCard(SecretItem item, bool isDark) {
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
  }"""
    
    new_google_card = """  Widget _buildGoogleCard(SecretItem item, bool isDark) {
    return UniversalCardWidget(
      cardType: item.cardType,
      secret: item.secret,
      cardholderName: item.username,
      expiryDate: item.expiryDate,
      cardProvider: item.cardProvider,
    );
  }"""
    
    content = content.replace(old_google_card, new_google_card)

    with open('lib/main.dart', 'w') as f:
        f.write(content)
    print("Success inserting UniversalCardWidget and replacing HomeScreen card")
else:
    print("start_homescreen not found")

