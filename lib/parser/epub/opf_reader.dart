import 'package:xml/xml.dart';

/// OPF 文件解析结果
class OpfData {
  /// OPF 所在目录路径（相对于 EPUB 根目录）
  final String opfDirPath;

  /// manifest: id → href 映射
  final Map<String, String> idToHref;

  /// manifest: href → media-type 映射
  final Map<String, String> hrefToMediaType;

  /// spine: 按阅读顺序排列的文件列表
  final List<String> spineHrefs;

  /// NCX 文件名
  final String ncxFileName;

  /// 封面文件名
  final String? coverFileName;

  /// 元数据
  final Map<String, String> metadata;

  const OpfData({
    required this.opfDirPath,
    required this.idToHref,
    required this.hrefToMediaType,
    required this.spineHrefs,
    required this.ncxFileName,
    this.coverFileName,
    this.metadata = const {},
  });
}

/// 解析 OPF 文件
/// 移植自 C++ OpfReader
class OpfReader {
  /// 解析 OPF 内容
  /// [xmlContent] OPF 文件 XML 内容
  /// [opfPath] OPF 文件在 EPUB 中的路径（用于计算目录前缀）
  static OpfData read(String xmlContent, String opfPath) {
    // 计算 OPF 目录前缀
    final lastSlash = opfPath.lastIndexOf('/');
    final opfDirPath = lastSlash >= 0 ? opfPath.substring(0, lastSlash + 1) : '';

    final idToHref = <String, String>{};
    final hrefToMediaType = <String, String>{};
    final spineHrefs = <String>[];
    var ncxFileName = '';
    String? coverFileName;
    final metadata = <String, String>{};

    try {
      final doc = XmlDocument.parse(xmlContent);
      final package = doc.rootElement;

      // === 解析 metadata ===
      for (final meta in package.findAllElements('metadata')) {
        for (final child in meta.children.whereType<XmlElement>()) {
          final localName = child.localName;
          final text = child.innerText.trim();
          if (text.isNotEmpty) {
            metadata[localName] = text;
          }
        }
        // 查找 cover meta
        for (final m in meta.findElements('meta')) {
          if (m.getAttribute('name') == 'cover') {
            final content = m.getAttribute('content');
            if (content != null) {
              // content 是 manifest 中的 id，后面解析完 manifest 后映射
              metadata['cover-id'] = content;
            }
          }
        }
      }

      // === 解析 manifest ===
      for (final manifest in package.findAllElements('manifest')) {
        for (final item in manifest.findElements('item')) {
          final id = item.getAttribute('id') ?? '';
          final href = _decodeHref(item.getAttribute('href') ?? '');
          final mediaType = item.getAttribute('media-type') ?? '';

          if (id.isNotEmpty && href.isNotEmpty) {
            idToHref[id] = href;
          }
          if (href.isNotEmpty && mediaType.isNotEmpty) {
            hrefToMediaType[href] = mediaType;
          }
        }
      }

      // === 解析 spine ===
      for (final spine in package.findAllElements('spine')) {
        // 获取 NCX 引用
        final toc = spine.getAttribute('toc');
        if (toc != null && idToHref.containsKey(toc)) {
          ncxFileName = idToHref[toc]!;
        }

        for (final itemref in spine.findElements('itemref')) {
          final idref = itemref.getAttribute('idref') ?? '';
          if (idref.isNotEmpty && idToHref.containsKey(idref)) {
            spineHrefs.add(idToHref[idref]!);
          }
        }
      }

      // === 解析 guide（封面等）===
      for (final guide in package.findAllElements('guide')) {
        for (final ref in guide.findElements('reference')) {
          final type = ref.getAttribute('type') ?? '';
          final href = _decodeHref(ref.getAttribute('href') ?? '');
          if (type == 'cover' && href.isNotEmpty) {
            coverFileName = href;
          }
        }
      }

      // 从 metadata cover-id 映射封面
      final coverId = metadata['cover-id'];
      if (coverFileName == null && coverId != null && idToHref.containsKey(coverId)) {
        coverFileName = idToHref[coverId];
      }

      // 如果没有找到 NCX，尝试查找 .ncx 文件
      if (ncxFileName.isEmpty) {
        for (final entry in idToHref.entries) {
          if (entry.value.endsWith('.ncx')) {
            ncxFileName = entry.value;
            break;
          }
        }
      }
    } catch (_) {
      // OPF 解析出错，返回空数据
    }

    return OpfData(
      opfDirPath: opfDirPath,
      idToHref: idToHref,
      hrefToMediaType: hrefToMediaType,
      spineHrefs: spineHrefs,
      ncxFileName: ncxFileName,
      coverFileName: coverFileName,
      metadata: metadata,
    );
  }

  /// 解码 href 中的 URL 编码
  static String _decodeHref(String href) {
    return Uri.decodeFull(href);
  }
}
