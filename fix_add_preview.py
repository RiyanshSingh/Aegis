import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

start_str = "  Widget _buildLiveCardPreview(bool isDark) {"
end_str = "  String _insertSpaces(String text) {"

if start_str in content and end_str in content:
    start_idx = content.find(start_str)
    end_idx = content.find(end_str)
    
    new_method = """  Widget _buildLiveCardPreview(bool isDark) {
    return UniversalCardWidget(
      cardType: _cardType,
      secret: _secretCtrl.text,
      cardholderName: _usernameCtrl.text,
      expiryDate: _expiryCtrl.text,
      cardProvider: _cardProvider,
    );
  }

"""
    content = content[:start_idx] + new_method + content[end_idx:]
    with open('lib/main.dart', 'w') as f:
        f.write(content)
    print("Success fixing AddEditItemPage preview")
else:
    print("Could not find start or end strings")
