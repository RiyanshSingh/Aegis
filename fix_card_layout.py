import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

old_ucw_decl = """class UniversalCardWidget extends StatelessWidget {
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
  });"""

new_ucw_decl = """class UniversalCardWidget extends StatelessWidget {
  final String bankName;
  final String cardType;
  final String secret;
  final String cardholderName;
  final String expiryDate;
  final String cardProvider;

  const UniversalCardWidget({
    super.key,
    required this.bankName,
    required this.cardType,
    required this.secret,
    required this.cardholderName,
    required this.expiryDate,
    required this.cardProvider,
  });"""

old_ucw_layout = """                Row(
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
                )"""

new_ucw_layout = """                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(bankName.isEmpty ? 'Bank Name' : bankName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(cardType, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
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
                    SizedBox(
                      width: 80,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expired Date', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                          Text(expiryDate.isEmpty ? '10/28' : expiryDate, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      alignment: Alignment.centerRight,
                      child: logo,
                    ),
                  ],
                )"""

old_home_call = """    return UniversalCardWidget(
      cardType: item.cardType,
      secret: item.secret,
      cardholderName: item.username,
      expiryDate: item.expiryDate,
      cardProvider: item.cardProvider,
    );"""

new_home_call = """    return UniversalCardWidget(
      bankName: item.title,
      cardType: item.cardType,
      secret: item.secret,
      cardholderName: item.username,
      expiryDate: item.expiryDate,
      cardProvider: item.cardProvider,
    );"""

old_add_call = """    return UniversalCardWidget(
      cardType: _cardType,
      secret: _secretCtrl.text,
      cardholderName: _usernameCtrl.text,
      expiryDate: _expiryCtrl.text,
      cardProvider: _cardProvider,
    );"""

new_add_call = """    return UniversalCardWidget(
      bankName: _titleCtrl.text,
      cardType: _cardType,
      secret: _secretCtrl.text,
      cardholderName: _usernameCtrl.text,
      expiryDate: _expiryCtrl.text,
      cardProvider: _cardProvider,
    );"""

old_view_call = """      return UniversalCardWidget(
        cardType: widget.item.cardType,
        secret: widget.item.secret,
        cardholderName: widget.item.username,
        expiryDate: widget.item.expiryDate,
        cardProvider: widget.item.cardProvider,
      );"""

new_view_call = """      return UniversalCardWidget(
        bankName: widget.item.title,
        cardType: widget.item.cardType,
        secret: widget.item.secret,
        cardholderName: widget.item.username,
        expiryDate: widget.item.expiryDate,
        cardProvider: widget.item.cardProvider,
      );"""

if old_ucw_decl in content: content = content.replace(old_ucw_decl, new_ucw_decl)
if old_ucw_layout in content: content = content.replace(old_ucw_layout, new_ucw_layout)
if old_home_call in content: content = content.replace(old_home_call, new_home_call)
if old_add_call in content: content = content.replace(old_add_call, new_add_call)
if old_view_call in content: content = content.replace(old_view_call, new_view_call)

with open('lib/main.dart', 'w') as f:
    f.write(content)
print("Success replacing card layouts")
