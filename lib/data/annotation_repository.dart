import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../text/annotation/text_annotation.dart';

/// 标注仓库 — 基于 SharedPreferences 的轻量持久化
class AnnotationRepository {
  static const _kPrefix = 'nbreader_annotations_';
  static AnnotationRepository? _instance;

  SharedPreferences? _prefs;

  AnnotationRepository._();

  static AnnotationRepository get instance {
    _instance ??= AnnotationRepository._();
    return _instance!;
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _key(String bookId) => '$_kPrefix$bookId';

  Future<List<TextAnnotation>> loadAnnotations(String bookId) async {
    final prefs = await _getPrefs();
    final jsonStr = prefs.getString(_key(bookId));
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list
          .map((e) => TextAnnotation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAnnotations(String bookId, List<TextAnnotation> annotations) async {
    final prefs = await _getPrefs();
    final jsonStr = jsonEncode(annotations.map((a) => a.toJson()).toList());
    await prefs.setString(_key(bookId), jsonStr);
  }

  Future<void> upsertAnnotation(String bookId, TextAnnotation annotation) async {
    final list = await loadAnnotations(bookId);
    final idx = list.indexWhere((a) => a.id == annotation.id);
    if (idx >= 0) {
      list[idx] = annotation;
    } else {
      list.add(annotation);
    }
    await saveAnnotations(bookId, list);
  }

  Future<void> deleteAnnotation(String bookId, String annotationId) async {
    final list = await loadAnnotations(bookId);
    list.removeWhere((a) => a.id == annotationId);
    await saveAnnotations(bookId, list);
  }

  Future<void> clearAnnotations(String bookId) async {
    final prefs = await _getPrefs();
    await prefs.remove(_key(bookId));
  }

  // === JSON 导入导出 ===

  /// 将指定书籍的标注导出为 JSON 字符串
  String exportToJson(String bookId, List<TextAnnotation> annotations) {
    final data = {
      'bookId': bookId,
      'version': 1,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'annotations': annotations.map((a) => a.toJson()).toList(),
    };
    return jsonEncode(data);
  }

  /// 从 JSON 字符串导入标注，返回导入的标注列表
  /// [merge] 为 true 时与已有标注合并（按 id 去重），否则替换
  Future<List<TextAnnotation>> importFromJson(
    String bookId,
    String jsonStr, {
    bool merge = true,
  }) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = (data['annotations'] as List<dynamic>)
        .map((e) => TextAnnotation.fromJson(e as Map<String, dynamic>))
        .toList();

    if (!merge) {
      await saveAnnotations(bookId, list);
      return list;
    }

    final existing = await loadAnnotations(bookId);
    final idSet = <String>{};
    final merged = <TextAnnotation>[];

    // 导入的优先（更新时间更新的覆盖）
    for (final a in list) {
      idSet.add(a.id);
      final old = existing.where((e) => e.id == a.id).firstOrNull;
      if (old != null && old.updatedAt > a.updatedAt) {
        merged.add(old);
      } else {
        merged.add(a);
      }
    }

    // 保留未在导入列表中的已有标注
    for (final a in existing) {
      if (!idSet.contains(a.id)) {
        merged.add(a);
      }
    }

    await saveAnnotations(bookId, merged);
    return merged;
  }
}
