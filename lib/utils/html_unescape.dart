/// HTML 实体解码工具
class HtmlUnescape {
  /// 常见 HTML 实体映射
  static const _entities = <String, String>{
    '&quot;': '"',
    '&apos;': "'",
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': '\u00A0',
    '&ndash;': '–',
    '&mdash;': '—',
    '&lsquo;': ''',
    '&rsquo;': ''',
    '&ldquo;': '"',
    '&rdquo;': '"',
    '&hellip;': '…',
    '&copy;': '©',
    '&reg;': '®',
    '&trade;': '™',
    '&times;': '×',
    '&divide;': '÷',
    '&bull;': '•',
    '&middot;': '·',
  };

  /// 解码 HTML 实体
  static String unescape(String text) {
    if (!text.contains('&')) return text;

    var result = text;

    // 解码命名实体
    for (final entry in _entities.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // 解码数字实体 (&#123; 或 &#x7B;)
    result = result.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    result = result.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );

    return result;
  }
}
