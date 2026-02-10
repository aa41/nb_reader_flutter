import 'package:xml/xml.dart';

/// NCX 导航节点
class NavPoint {
  final int order;
  final int level;
  final String text;
  final String contentHref;

  const NavPoint({
    required this.order,
    required this.level,
    required this.text,
    required this.contentHref,
  });

  @override
  String toString() => 'NavPoint(order=$order, text=$text, href=$contentHref)';
}

/// 解析 NCX (Navigation Control for XML) 文件
/// 移植自 C++ NcxReader
class NcxReader {
  /// 解析 NCX 内容
  /// 返回按 playOrder 排序的 NavPoint 列表
  static List<NavPoint> read(String xmlContent) {
    final points = <NavPoint>[];
    var autoOrder = 0;

    try {
      final doc = XmlDocument.parse(xmlContent);

      // 查找 navMap
      final navMaps = doc.findAllElements('navMap');
      for (final navMap in navMaps) {
        _parseNavPoints(navMap, points, 0, autoOrder);
      }

      // 按 order 排序
      points.sort((a, b) => a.order.compareTo(b.order));
    } catch (_) {
      // NCX 解析出错
    }

    return points;
  }

  /// 递归解析 navPoint 元素
  static void _parseNavPoints(
    XmlElement parent,
    List<NavPoint> points,
    int level,
    int autoOrder,
  ) {
    for (final navPoint in parent.findElements('navPoint')) {
      // 读取 playOrder
      final orderStr = navPoint.getAttribute('playOrder');
      final order = orderStr != null ? int.tryParse(orderStr) ?? autoOrder++ : autoOrder++;

      // 读取文本标签 <navLabel><text>...</text></navLabel>
      var text = '';
      for (final label in navPoint.findElements('navLabel')) {
        for (final textElem in label.findElements('text')) {
          text = textElem.innerText.trim();
          if (text.isNotEmpty) break;
        }
        if (text.isNotEmpty) break;
      }
      if (text.isEmpty) text = '...';

      // 读取内容引用 <content src="..."/>
      var contentHref = '';
      for (final content in navPoint.findElements('content')) {
        final src = content.getAttribute('src');
        if (src != null && src.isNotEmpty) {
          contentHref = Uri.decodeFull(src);
          break;
        }
      }

      if (contentHref.isNotEmpty) {
        points.add(NavPoint(
          order: order,
          level: level,
          text: text,
          contentHref: contentHref,
        ));
      }

      // 递归处理嵌套的 navPoint
      _parseNavPoints(navPoint, points, level + 1, autoOrder);
    }
  }
}
