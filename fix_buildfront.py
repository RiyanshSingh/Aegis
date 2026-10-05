import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

old_buildfront = """  Widget _buildFront(Color bgColor, Color textColor, bool isDark) {
    return Container(
      width: double.infinity,
      height: 240,"""

new_buildfront = """  Widget _buildFront(Color bgColor, Color textColor, bool isDark) {
    if (widget.item.isCard) {
      return UniversalCardWidget(
        cardType: widget.item.cardType,
        secret: widget.item.secret,
        cardholderName: widget.item.username,
        expiryDate: widget.item.expiryDate,
        cardProvider: widget.item.cardProvider,
      );
    }
    return Container(
      width: double.infinity,
      height: 240,"""

if old_buildfront in content:
    content = content.replace(old_buildfront, new_buildfront)
    with open('lib/main.dart', 'w') as f:
        f.write(content)
    print("Success fixing _buildFront")
else:
    print("Could not find old_buildfront")

