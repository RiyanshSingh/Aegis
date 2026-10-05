import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

# Fix CardPattern gradient
old_gradient = """                colors: isDark 
                  ? [const Color(0xFF2A2A2A), const Color(0xFF0A0A0A)]
                  : [AppColors.walletBlue, const Color(0xFF9CCC65)],"""
new_gradient = """                colors: const [Color(0xFFE8B79B), Color(0xFF67C7A8)],"""
content = content.replace(old_gradient, new_gradient)

# Fix getCardLogo
old_getcardlogo = """Widget getCardLogo(SecretItem item) {
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

  Widget? logo;
  if (detected == 'Visa') {
    logo = const Text('VISA', style: TextStyle(color: Color(0xFF1A1F71), fontWeight: FontWeight.w900, fontSize: 20, fontStyle: FontStyle.italic));
  } else if (detected == 'Mastercard') {
    logo = SizedBox(
      width: 36, height: 22,
      child: Stack(
        children: [
          Positioned(left: 0, child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red.withOpacity(0.9)))),
          Positioned(right: 0, child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange.withOpacity(0.9)))),
        ],
      ),
    );
  } else if (detected == 'RuPay') {
    logo = const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Ru', style: TextStyle(color: Color(0xFFE35205), fontWeight: FontWeight.w900, fontSize: 16, fontStyle: FontStyle.italic)),
        Text('Pay', style: TextStyle(color: Color(0xFF1A1F71), fontWeight: FontWeight.w900, fontSize: 16, fontStyle: FontStyle.italic)),
      ],
    );
  }
  
  if (logo == null) return const SizedBox();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.4), borderRadius: BorderRadius.circular(6)),
    child: logo,
  );
}"""
new_getcardlogo = """Widget getCardLogo(SecretItem item) {
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
}"""
content = content.replace(old_getcardlogo, new_getcardlogo)

with open('lib/main.dart', 'w') as f:
    f.write(content)
