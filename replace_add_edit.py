import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

# I will find the exact start and end of AddEditItemPage
start_str = "class AddEditItemPage extends StatefulWidget {"
end_str = "class SettingsScreen extends StatelessWidget {"

if start_str in content and end_str in content:
    start_idx = content.find(start_str)
    end_idx = content.find(end_str)
    
    old_code = content[start_idx:end_idx]
    
    new_code = """class AddEditItemPage extends StatefulWidget {
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
    final e = widget.existingItem;
    _isCard = e?.isCard ?? true; // Default to card to show off the UI
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
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      final newItem = SecretItem(
        id: widget.existingItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleCtrl.text.isEmpty ? (_isCard ? 'My Card' : 'New Secret') : _titleCtrl.text,
        username: _usernameCtrl.text,
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
              child: Icon(Icons.chevron_left, color: AppColors.walletBlue),
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
                              color: _isCard ? AppColors.walletBlue : (isDark ? AppColors.darkCard : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text('Card', style: TextStyle(color: _isCard ? Colors.white : (isDark ? Colors.white : Colors.black), fontWeight: FontWeight.bold)),
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
                              color: !_isCard ? AppColors.walletBlue : (isDark ? AppColors.darkCard : Colors.white),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text('Password', style: TextStyle(color: !_isCard ? Colors.white : (isDark ? Colors.white : Colors.black), fontWeight: FontWeight.bold)),
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
                label: _isCard ? 'Cardholder Name' : 'Title (e.g. Netflix)',
                controller: _titleCtrl,
                hint: 'Rabbi Rezwan',
              ),
              const SizedBox(height: 20),

              if (!_isCard) ...[
                _buildInputGroup(
                  isDark,
                  label: 'Username / Email',
                  controller: _usernameCtrl,
                  hint: 'user@example.com',
                ),
                const SizedBox(height: 20),
              ],

              _buildInputGroup(
                isDark,
                label: _isCard ? 'Card Number' : 'Password',
                controller: _secretCtrl,
                hint: _isCard ? '0123456789' : '••••••••',
                keyboardType: _isCard ? TextInputType.number : TextInputType.text,
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
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: AppColors.walletBlue,
                  foregroundColor: Colors.white,
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

  Widget _buildLiveCardPreview(bool isDark) {
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
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Debit', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Icon(Icons.contactless_rounded, color: Colors.white),
                  ],
                ),
                const Spacer(),
                Text(
                  _secretCtrl.text.isEmpty ? '8763 2736 9873 0329' : _insertSpaces(_secretCtrl.text), 
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
                          Text(_titleCtrl.text.isEmpty ? 'Rabbi Rezwan' : _titleCtrl.text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expired Date', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w500)),
                          Text(_expiryCtrl.text.isEmpty ? '10/28' : _expiryCtrl.text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), shape: BoxShape.circle)),
                        Transform.translate(offset: const Offset(-10, 0), child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.9), shape: BoxShape.circle))),
                      ],
                    ),
                  ],
                )
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

  Widget _buildInputGroup(bool isDark, {required String label, required TextEditingController controller, required String hint, bool obscureText = false, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: (v) => v!.isEmpty ? 'Required' : null,
          onChanged: (v) => setState(() {}),
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.normal),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }
}

"""
    new_content = content[:start_idx] + new_code + content[end_idx:]
    with open('lib/main.dart', 'w') as f:
        f.write(new_content)
    print("Success")
else:
    print("Could not find start or end strings")
