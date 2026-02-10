import 'dart:convert';
import 'dart:typed_data';

/// 编码检测与转换工具
class EncodingDetector {
  static const String encodingUtf8 = 'utf-8';
  static const String encodingUtf16le = 'utf-16le';
  static const String encodingUtf16be = 'utf-16be';
  static const String encodingGbk = 'gbk';

  /// 检测字节数据的编码
  static String detect(Uint8List bytes) {
    // 1. BOM 检测
    final bom = detectBOM(bytes);
    if (bom != null) return bom;

    // 2. UTF-8 验证
    if (_isValidUtf8(bytes)) return encodingUtf8;

    // 3. 默认假定 GBK（中文 TXT 文件最常见的非 UTF-8 编码）
    return encodingGbk;
  }

  /// 检测 BOM 头
  static String? detectBOM(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return encodingUtf8;
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) return encodingUtf16le;
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) return encodingUtf16be;
    }
    return null;
  }

  /// 获取 BOM 字节长度
  static int bomLength(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 3;
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) return 2;
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) return 2;
    }
    return 0;
  }

  /// 验证是否为有效 UTF-8
  static bool _isValidUtf8(Uint8List bytes) {
    try {
      const Utf8Decoder(allowMalformed: false).convert(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 解码字节为字符串
  static String decode(Uint8List bytes, String encoding) {
    final bomLen = bomLength(bytes);
    final data = bomLen > 0 ? bytes.sublist(bomLen) : bytes;

    switch (encoding.toLowerCase()) {
      case 'utf-8':
        return const Utf8Decoder(allowMalformed: true).convert(data);
      case 'utf-16le':
        return _decodeUtf16(data, littleEndian: true);
      case 'utf-16be':
        return _decodeUtf16(data, littleEndian: false);
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        return _decodeGBK(data);
      default:
        return const Utf8Decoder(allowMalformed: true).convert(data);
    }
  }

  static String _decodeUtf16(Uint8List data, {required bool littleEndian}) {
    final buffer = StringBuffer();
    for (int i = 0; i + 1 < data.length; i += 2) {
      final code = littleEndian
          ? (data[i] | (data[i + 1] << 8))
          : ((data[i] << 8) | data[i + 1]);
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  /// GBK 解码
  /// TODO: 集成完整 GBK codec（如 enough_convert 或 gbk_codec）
  /// 当前策略：尝试 UTF-8，失败则使用 latin1 作为 fallback
  static String _decodeGBK(Uint8List data) {
    try {
      return const Utf8Decoder().convert(data);
    } catch (_) {
      return latin1.decode(data);
    }
  }
}
