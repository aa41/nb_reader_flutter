import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../text/entity/text_chapter.dart';
import '../../text/entity/text_content.dart';
import '../format_plugin.dart';
import 'container_reader.dart';
import 'ncx_reader.dart';
import 'opf_reader.dart';
import 'xhtml_content_reader.dart';

/// EPUB 格式解析插件
/// 移植自 C++ OebPlugin
///
/// 解析流程：
/// 1. 解压 EPUB (ZIP) 文件
/// 2. 读取 META-INF/container.xml → 获取 OPF 路径
/// 3. 读取 OPF → 获取 manifest/spine/NCX 路径/metadata
/// 4. 读取 NCX → 获取章节导航信息
/// 5. 按需读取 XHTML 章节内容 → 通过 XhtmlContentReader 转换为 TextTag 列表
class EpubPlugin implements FormatPlugin {
  Archive? _archive;
  OpfData? _opfData;
  List<NavPoint> _navPoints = [];
  List<TextChapter> _chapters = [];
  Map<String, String> _metadata = {};

  /// EPUB 内部文件名 → 文件内容的缓存
  final Map<String, ArchiveFile> _fileIndex = {};

  @override
  Future<void> openBook(String bookPath) async {
    // 读取 EPUB 文件
    final bytes = await File(bookPath).readAsBytes();
    _archive = ZipDecoder().decodeBytes(bytes);

    // 建立文件索引（路径 → ArchiveFile）
    _fileIndex.clear();
    for (final file in _archive!) {
      if (!file.isFile) continue;
      // 统一使用不带前导斜杠的路径
      final name = file.name.startsWith('/') ? file.name.substring(1) : file.name;
      _fileIndex[name] = file;
    }

    // 步骤 1：读取 container.xml
    final containerXml = _readFileAsString('META-INF/container.xml');
    if (containerXml == null) {
      throw FormatException('EPUB 缺少 META-INF/container.xml');
    }

    final opfPath = ContainerReader.readOpfPath(containerXml);
    if (opfPath == null) {
      throw const FormatException('container.xml 中未找到 OPF 路径');
    }

    // 步骤 2：读取 OPF
    final opfXml = _readFileAsString(opfPath);
    if (opfXml == null) {
      throw FormatException('EPUB 缺少 OPF 文件: $opfPath');
    }

    _opfData = OpfReader.read(opfXml, opfPath);
    _metadata = Map<String, String>.from(_opfData!.metadata);

    // 步骤 3：读取 NCX
    final ncxPath = _resolvePathInEpub(_opfData!.ncxFileName);
    final ncxXml = _readFileAsString(ncxPath);
    if (ncxXml != null) {
      _navPoints = NcxReader.read(ncxXml);
    }

    // 构建章节列表
    _buildChapters();
  }

  /// 构建章节列表
  void _buildChapters() {
    _chapters.clear();

    final spineCount = _opfData?.spineHrefs.length ?? 0;
    final navCount = _navPoints.length;

    // 判断 NCX 是否提供了足够的章节信息
    // 当 NCX navPoints 数量远少于 spine（如仅1个"开始"），说明 NCX 不完整，
    // 应使用 spine 构建章节列表
    final useNcx = navCount > 0 &&
        (spineCount == 0 || navCount >= spineCount * 0.3);

    if (useNcx) {
      // 根据 NCX navPoints 构建章节
      // 保留完整 href（含 #fragment），用于单文件多章节的内容拆分
      for (int i = 0; i < _navPoints.length; i++) {
        final np = _navPoints[i];
        _chapters.add(TextChapter(
          url: np.contentHref,
          title: np.text,
          startIndex: i,
          endIndex: i,
        ));
      }
    } else if (_opfData != null && _opfData!.spineHrefs.isNotEmpty) {
      // NCX 不完整或不存在，使用 spine 顺序，并尝试从文件内容提取章节标题
      for (int i = 0; i < _opfData!.spineHrefs.length; i++) {
        final href = _opfData!.spineHrefs[i];
        final title = _extractChapterTitle(href) ?? '第${i + 1}章';
        _chapters.add(TextChapter(
          url: href,
          title: title,
          startIndex: i,
          endIndex: i,
        ));
      }
    }
  }

  /// 从 XHTML/HTML 文件内容中提取章节标题
  /// 优先查找 <h1>-<h3> 标签，其次查找第一个粗体文本
  String? _extractChapterTitle(String href) {
    final filePath = _resolvePathInEpub(href);
    final content = _readFileAsString(filePath);
    if (content == null) return null;

    // 只解析文件前2000个字符以提高性能，标题通常在文件开头
    final snippet = content.length > 2000 ? content.substring(0, 2000) : content;

    // 尝试匹配 <h1>~<h3> 标签内容
    final headingRegex = RegExp(r'<h[1-3][^>]*>(.*?)</h[1-3]>', caseSensitive: false, dotAll: true);
    final headingMatch = headingRegex.firstMatch(snippet);
    if (headingMatch != null) {
      final title = _stripHtmlTags(headingMatch.group(1) ?? '').trim();
      if (title.isNotEmpty) return title;
    }

    // 尝试匹配 <span class="bold">...</span>（Calibre 生成的常见格式）
    final boldSpanRegex = RegExp(
      r'<span[^>]*class="[^"]*bold[^"]*"[^>]*>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );
    final boldMatch = boldSpanRegex.firstMatch(snippet);
    if (boldMatch != null) {
      final title = _stripHtmlTags(boldMatch.group(1) ?? '').trim();
      if (title.isNotEmpty) return title;
    }

    // 尝试匹配 <b> 或 <strong> 标签
    final bRegex = RegExp(r'<(?:b|strong)[^>]*>(.*?)</(?:b|strong)>', caseSensitive: false, dotAll: true);
    final bMatch = bRegex.firstMatch(snippet);
    if (bMatch != null) {
      final title = _stripHtmlTags(bMatch.group(1) ?? '').trim();
      if (title.isNotEmpty) return title;
    }

    return null;
  }

  /// 移除 HTML 标签，返回纯文本
  static String _stripHtmlTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  @override
  String getEncoding() => 'utf-8'; // EPUB 标准要求 UTF-8

  @override
  String getLanguage() => _metadata['language'] ?? '';

  @override
  List<TextChapter> getChapters() => _chapters;

  @override
  TextContent? getChapterContent(TextChapter chapter) {
    final opf = _opfData;
    if (opf == null) return null;

    // 解析 URL 和片段锡点（如 "chapter.xhtml#sigil_toc_id_5"）
    final parts = chapter.url.split('#');
    final fileHref = parts.first;
    final fragmentId = parts.length > 1 ? parts[1] : null;

    // 解析 XHTML 文件路径
    final xhtmlPath = _resolvePathInEpub(fileHref);
    final xhtmlContent = _readFileAsString(xhtmlPath);
    if (xhtmlContent == null) return null;

    // 查找下一个章节的片段 ID（同一文件内的下一个锚点）
    // 注意：即使当前章节没有 fragment（如文件的第一个章节），
    // 也需要查找 endFragmentId，以避免加载整个文件内容
    String? endFragmentId;
    final chapterIdx = chapter.startIndex;
    if (chapterIdx >= 0 && chapterIdx < _chapters.length) {
      for (int i = chapterIdx + 1; i < _chapters.length; i++) {
        final nextParts = _chapters[i].url.split('#');
        final nextFile = nextParts.first;
        if (nextFile == fileHref && nextParts.length > 1) {
          endFragmentId = nextParts[1];
          break;
        } else if (nextFile != fileHref) {
          // 下一章节在不同文件，当前章节到文件末尾
          break;
        }
      }
    }

    // 为图片提供相对于 XHTML 文件的路径解析
    final xhtmlDir = xhtmlPath.contains('/')
        ? xhtmlPath.substring(0, xhtmlPath.lastIndexOf('/') + 1)
        : '';

    return XhtmlContentReader.parse(
      xhtmlContent,
      imageDataResolver: (src) {
        // 先尝试相对于 XHTML 文件的路径（规范化以处理 .. 等片段）
        final relativeToXhtml = p.normalize('$xhtmlDir$src').replaceAll('\\', '/');
        final result = readFileAsBytes(relativeToXhtml);
        if (result != null) return result;
        // 再尝试相对于 OPF 的路径
        final resolved = _resolvePathInEpub(src);
        return readFileAsBytes(resolved);
      },
      startFragmentId: fragmentId,
      endFragmentId: endFragmentId,
    );
  }

  @override
  String? getChapterPlainText(TextChapter chapter) {
    // 从解析后的 tag 结构构建纯文本，而非直接 strip HTML。
    // 这样可以正确尊重 fragment 边界（startFragmentId / endFragmentId），
    // 并保证纯文本与 tag 内容完全一致，便于搜索偏移精确映射。
    final content = getChapterContent(chapter);
    if (content == null) return null;
    return content.toPlainText();
  }

  @override
  ImageDataResolver? get imageDataResolver {
    return (String imagePath) {
      final resolved = _resolvePathInEpub(imagePath);
      return readFileAsBytes(resolved);
    };
  }

  /// 将 EPUB 内部的相对路径解析为完整的 ZIP 内路径
  String _resolvePathInEpub(String href) {
    final opf = _opfData;
    if (opf == null) return href;

    // 如果 href 已经是完整路径，直接使用
    if (_fileIndex.containsKey(href)) return href;

    // 拼接 OPF 目录前缀
    final resolved = '${opf.opfDirPath}$href';
    if (_fileIndex.containsKey(resolved)) return resolved;

    // 尝试使用 path 规范化
    final normalized = p.normalize(resolved).replaceAll('\\', '/');
    if (_fileIndex.containsKey(normalized)) return normalized;

    // 返回原始拼接结果
    return resolved;
  }

  /// 读取 EPUB 内部文件为字符串
  String? _readFileAsString(String path) {
    final file = _fileIndex[path];
    if (file == null) return null;

    return utf8.decode(file.content, allowMalformed: true);
  }

  /// 读取 EPUB 内部文件为字节数据
  Uint8List? readFileAsBytes(String path) {
    final file = _fileIndex[path];
    if (file == null) return null;

    return file.content;
  }

  /// 获取书籍标题
  String? get title => _metadata['title'];

  /// 获取书籍作者
  String? get author => _metadata['creator'];

  /// 获取封面图片数据
  Uint8List? getCoverImage() {
    final opf = _opfData;
    if (opf == null || opf.coverFileName == null) return null;
    final coverPath = _resolvePathInEpub(opf.coverFileName!);
    return readFileAsBytes(coverPath);
  }

  @override
  void release() {
    _archive = null;
    _fileIndex.clear();
    _opfData = null;
    _navPoints = [];
    _chapters = [];
    _metadata = {};
  }
}
