/// 支持的书本格式
enum BookType {
  txt,
  epub,
  markdown;

  /// 从文件扩展名获取 BookType
  static BookType? fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.txt':
        return BookType.txt;
      case '.epub':
        return BookType.epub;
      case '.md':
      case '.markdown':
        return BookType.markdown;
      default:
        return null;
    }
  }
}
