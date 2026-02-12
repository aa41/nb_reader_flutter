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
}
