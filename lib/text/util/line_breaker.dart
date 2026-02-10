/// 行断裂工具 - 简化版 Unicode UAX#14 实现
///
/// 规则简述：
/// - CJK 字符之间均可断行
/// - Latin 字符按空格/连字符断行
/// - 标点符号遵循基本的禁止行首/行尾规则
class LineBreaker {
  /// 不允许断行
  static const int nobreak = 0;

  /// 允许断行
  static const int allowBreak = 1;

  /// 必须断行
  static const int mustBreak = 2;

  /// 不允许在此字符前断行的字符集（行首禁则）
  static const String _noBreakBefore =
      '!),.:;?]}¢°·ˇˉ―‖…‰′″›℃∶、。〃〉》」』】〕〗〞︶︺︾﹀﹄﹚﹜﹞！），．：；？］｝～';

  /// 不允许在此字符后断行的字符集（行尾禁则）
  static const String _noBreakAfter =
      '([{\u00a3\u00a5\u00b7\u2018\u201c\u3008\u300a\u300c\u300e\u3010\u3014\u3016\u301d\ufe35\ufe39\ufe3d\uff08\uff3b\uff5b\uffe1\uffe5';

  /// 计算字符数组的断行属性
  /// [data] 字符数据
  /// [offset] 起始偏移
  /// [length] 长度
  /// [language] 语言
  /// [result] 输出结果数组，每个位置表示该字符之后是否可以断行
  static void setLineBreak(
    List<int> data,
    int offset,
    int length,
    String language,
    List<int> result,
  ) {
    if (length == 0) return;

    for (int i = 0; i < length; i++) {
      final charCode = data[offset + i];
      final char = String.fromCharCode(charCode);

      if (i == length - 1) {
        // 最后一个字符后必须断行
        result[i] = mustBreak;
        continue;
      }

      // 获取下一个字符
      final nextCharCode = data[offset + i + 1];
      final nextChar = String.fromCharCode(nextCharCode);

      // 检查行首禁则：下一个字符不允许出现在行首
      if (_noBreakBefore.contains(nextChar)) {
        result[i] = nobreak;
        continue;
      }

      // 检查行尾禁则：当前字符不允许出现在行尾
      if (_noBreakAfter.contains(char)) {
        result[i] = nobreak;
        continue;
      }

      // CJK 字符之间可断行
      if (_isCJK(charCode) || _isCJK(nextCharCode)) {
        result[i] = allowBreak;
        continue;
      }

      // 连字符后允许断行
      if (char == '-') {
        result[i] = allowBreak;
        continue;
      }

      // 空格后允许断行
      if (_isWhitespace(charCode)) {
        result[i] = allowBreak;
        continue;
      }

      // 默认不断行（Latin 单词内部）
      result[i] = nobreak;
    }
  }

  /// 判断是否是 CJK 字符
  static bool _isCJK(int charCode) {
    return (charCode >= 0x4E00 && charCode <= 0x9FFF) || // CJK Unified Ideographs
        (charCode >= 0x3400 && charCode <= 0x4DBF) || // CJK Extension A
        (charCode >= 0x3000 && charCode <= 0x303F) || // CJK Symbols and Punctuation
        (charCode >= 0xFF00 && charCode <= 0xFFEF) || // Fullwidth Forms
        (charCode >= 0x3040 && charCode <= 0x309F) || // Hiragana
        (charCode >= 0x30A0 && charCode <= 0x30FF) || // Katakana
        (charCode >= 0xAC00 && charCode <= 0xD7AF); // Hangul
  }

  /// 判断是否是空白字符
  static bool _isWhitespace(int charCode) {
    return charCode == 0x20 || // Space
        charCode == 0x09 || // Tab
        charCode == 0x0A || // LF
        charCode == 0x0D; // CR
  }
}
