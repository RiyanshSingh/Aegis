import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

target = "  Widget _buildLiveCardPreview(bool isDark) {"
new_method = """  Widget _buildInputGroup(
    bool isDark, {
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
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
          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3)),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }

"""

if target in content:
    content = content.replace(target, new_method + target)
    with open('lib/main.dart', 'w') as f:
        f.write(content)
    print("Success injecting _buildInputGroup")
else:
    print("Could not find target")

