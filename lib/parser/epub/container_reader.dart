import 'package:xml/xml.dart';

/// 解析 META-INF/container.xml 获取 OPF 文件路径
class ContainerReader {
  /// 从 container.xml 内容中提取 OPF 路径
  static String? readOpfPath(String xmlContent) {
    try {
      final doc = XmlDocument.parse(xmlContent);
      // 查找 <rootfile full-path="...">
      final rootfiles = doc.findAllElements('rootfile');
      for (final rf in rootfiles) {
        final fullPath = rf.getAttribute('full-path');
        if (fullPath != null && fullPath.isNotEmpty) {
          return fullPath;
        }
      }
    } catch (_) {
      // 解析失败
    }
    return null;
  }
}
