import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/book_entity.dart';
import '../../core/book_type.dart';
import '../../data/book_repository.dart';
import '../../parser/epub/epub_plugin.dart';
import '../read/read_page.dart';

/// 书架页面
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  List<BookEntity> _books = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await _ensureTestMarkdown();
    await _loadBooks();
  }

  /// 首次启动时将内置测试 Markdown 复制到文档目录并添加到书架
  Future<void> _ensureTestMarkdown() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final destFile = File(p.join(docDir.path, 'test_markdown.md'));

      // 每次都覆盖写入，保证内容最新
      final data = await rootBundle.loadString('assets/test_markdown.md');
      await destFile.writeAsString(data);

      // 添加到书架（BookRepository 按 url 去重）
      final book = BookEntity(
        id: 'builtin_test_markdown',
        title: 'Markdown 渲染测试',
        url: destFile.path,
        type: BookType.md,
      );
      await BookRepository.instance.addBook(book);
    } catch (e) {
      debugPrint('ensureTestMarkdown error: $e');
    }
  }

  Future<void> _loadBooks() async {
    final books = await BookRepository.instance.loadBooks();
    if (mounted) {
      setState(() {
        _books = books;
        _isLoading = false;
      });
    }
  }

  Future<void> _importBook() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub', 'md', 'markdown'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final filePath = file.path;
      if (filePath == null) return;

      final ext = p.extension(filePath).toLowerCase();
      final bookType = BookType.fromExtension(ext);
      if (bookType == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不支持的文件格式')),
          );
        }
        return;
      }

      String title = p.basenameWithoutExtension(filePath);
      String? author;

      // EPUB 尝试读取元数据
      if (bookType == BookType.epub) {
        try {
          final plugin = EpubPlugin();
          await plugin.openBook(filePath);
          if (plugin.title != null && plugin.title!.isNotEmpty) title = plugin.title!;
          if (plugin.author != null && plugin.author!.isNotEmpty) author = plugin.author;
          plugin.release();
        } catch (_) {
          // 忽略元数据读取失败
        }
      }

      // 生成唯一 ID
      final id = '${DateTime.now().millisecondsSinceEpoch}_${filePath.hashCode.abs()}';

      final book = BookEntity(
        id: id,
        title: title,
        url: filePath,
        type: bookType,
        author: author,
      );

      final savedBook = await BookRepository.instance.addBook(book);
      await _loadBooks();

      if (mounted) {
        _openBook(savedBook);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  void _openBook(BookEntity book) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReadPage(book: book)),
    );
    // 返回后刷新书架
    _loadBooks();
  }

  Future<void> _deleteBook(BookEntity book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定要从书架中删除「${book.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await BookRepository.instance.removeBook(book.id);
      _loadBooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '导入书籍',
            onPressed: _importBook,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? _buildEmptyState()
              : _buildBookGrid(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('书架空空如也',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importBook,
            icon: const Icon(Icons.add),
            label: const Text('添加书籍'),
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = _books[index];
        return _BookItem(
          book: book,
          onTap: () => _openBook(book),
          onLongPress: () => _deleteBook(book),
        );
      },
    );
  }
}

class _BookItem extends StatelessWidget {
  final BookEntity book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BookItem({
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        children: [
          // 书籍封面
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _coverColor(book),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(2, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (book.author != null && book.author!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      book.author!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 书名
          Text(
            book.title,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Color _coverColor(BookEntity book) {
    // 根据书名生成固定颜色
    final hash = book.title.hashCode;
    final colors = [
      const Color(0xFF5C6BC0),
      const Color(0xFF26A69A),
      const Color(0xFFEF5350),
      const Color(0xFFAB47BC),
      const Color(0xFF42A5F5),
      const Color(0xFFFF7043),
      const Color(0xFF66BB6A),
      const Color(0xFF8D6E63),
    ];
    return colors[hash.abs() % colors.length];
  }
}
