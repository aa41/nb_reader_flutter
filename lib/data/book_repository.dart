import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/book_entity.dart';

/// 书籍仓库 — 基于 SharedPreferences 的轻量持久化
class BookRepository {
  static const _kBookShelfKey = 'nbreader_bookshelf';
  static BookRepository? _instance;

  SharedPreferences? _prefs;

  BookRepository._();

  static BookRepository get instance {
    _instance ??= BookRepository._();
    return _instance!;
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 加载书架列表（按最近阅读时间降序排列）
  Future<List<BookEntity>> loadBooks() async {
    final prefs = await _getPrefs();
    final jsonStr = prefs.getString(_kBookShelfKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final books = list
          .map((e) => BookEntity.fromJson(e as Map<String, dynamic>))
          .toList();
      // 按最近阅读时间降序排列
      books.sort((a, b) {
        final ta = a.lastReadTime ?? DateTime(2000);
        final tb = b.lastReadTime ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      return books;
    } catch (_) {
      return [];
    }
  }

  /// 添加书籍（按 url 去重）
  Future<BookEntity> addBook(BookEntity book) async {
    final books = await loadBooks();
    // 去重
    final existing = books.indexWhere((b) => b.url == book.url);
    if (existing >= 0) {
      // 已存在，更新类型和最近阅读时间（修复旧数据类型不正确的问题）
      final updated = books[existing].copyWith(
        type: book.type,
        title: book.title,
        author: book.author,
        lastReadTime: DateTime.now(),
      );
      books[existing] = updated;
      await _saveBooks(books);
      return updated;
    }

    final newBook = book.copyWith(lastReadTime: DateTime.now());
    books.insert(0, newBook);
    await _saveBooks(books);
    return newBook;
  }

  /// 删除书籍
  Future<void> removeBook(String bookId) async {
    final books = await loadBooks();
    books.removeWhere((b) => b.id == bookId);
    await _saveBooks(books);
  }

  /// 更新阅读进度（基于精确文本位置）
  Future<void> updateReadProgress(
    String bookId, {
    required int chapterIndex,
    required int paragraphIndex,
    required int elementIndex,
    required int charIndex,
  }) async {
    final books = await loadBooks();
    final idx = books.indexWhere((b) => b.id == bookId);
    if (idx < 0) return;

    books[idx] = books[idx].copyWith(
      lastChapterIndex: chapterIndex,
      lastParagraphIndex: paragraphIndex,
      lastElementIndex: elementIndex,
      lastCharIndex: charIndex,
      lastReadTime: DateTime.now(),
    );
    await _saveBooks(books);
  }

  /// 获取指定书籍
  Future<BookEntity?> getBook(String bookId) async {
    final books = await loadBooks();
    try {
      return books.firstWhere((b) => b.id == bookId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveBooks(List<BookEntity> books) async {
    final prefs = await _getPrefs();
    final jsonStr = jsonEncode(books.map((b) => b.toJson()).toList());
    await prefs.setString(_kBookShelfKey, jsonStr);
  }
}
