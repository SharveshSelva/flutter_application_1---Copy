import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory_models.dart';
import 'memory_ai_service.dart';

class MemoryRepository {
  MemoryRepository({MemoryAIService? aiService})
      : _firestore = FirebaseFirestore.instance,
        _auth = FirebaseAuth.instance,
        _aiService = aiService ?? MemoryAIService() {
    _artifactController = StreamController<List<MemoryArtifact>>.broadcast(
      onListen: () async {
        await _initFuture;
        _artifactController.add(List.unmodifiable(_artifacts));
      },
    );
    _initFuture = _init();
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final MemoryAIService _aiService;

  late final Future<void> _initFuture;
  late SharedPreferences _prefs;
  final List<MemoryArtifact> _artifacts = [];
  late final StreamController<List<MemoryArtifact>> _artifactController;
  StreamSubscription<User?>? _authSubscription;
  String? _lastUid;

  static const String _prefsKey = 'memory_artifacts';

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _lastUid = _auth.currentUser?.uid;
    await _loadArtifactsFromPrefs();
    _authSubscription = _auth.authStateChanges().listen((user) async {
      _lastUid = user?.uid;
      await _loadArtifactsFromPrefs();
    });
  }

  Future<void> _loadArtifactsFromPrefs() async {
    final stored = _prefs.getStringList(_storageKey) ?? [];
    _artifacts
      ..clear()
      ..addAll(
        stored.map((item) {
          final map = jsonDecode(item) as Map<String, dynamic>;
          return MemoryArtifact.fromMap(map);
        }),
      )
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _artifactController.add(List.unmodifiable(_artifacts));
  }

  Future<void> _persistArtifacts() async {
    final payload = _artifacts.map((artifact) => jsonEncode(artifact.toMap())).toList();
    await _prefs.setStringList(_storageKey, payload);
  }

  Stream<List<MemoryArtifact>> streamArtifacts() {
    return _artifactController.stream;
  }

  Future<List<MemoryArtifact>> fetchArtifacts() async {
    await _initFuture;
    return List.unmodifiable(_artifacts);
  }

  Future<MemoryArtifact?> uploadArtifact({
    required XFile file,
    List<String> tags = const [],
    String? notes,
  }) async {
    await _initFuture;
    if (kIsWeb) {
      throw UnsupportedError('Local reminiscence storage is not supported on web builds.');
    }

    final analysis = await _aiService.analyzeArtifact(file: file, manualTags: tags);
    final path = await _saveFileLocally(file);

    final newArtifact = MemoryArtifact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      mediaPath: path,
      mediaType: _isVideo(file.path) ? 'video' : 'image',
      tags: tags,
      autoLabels: analysis.labels,
      primaryCategory: analysis.primaryCategory,
      createdAt: DateTime.now(),
      notes: notes,
    );

    _artifacts.insert(0, newArtifact);
    await _persistArtifacts();
    _artifactController.add(List.unmodifiable(_artifacts));
    return newArtifact;
  }

  Future<bool> deleteArtifact(String artifactId) async {
    await _initFuture;
    final index = _artifacts.indexWhere((a) => a.id == artifactId);
    if (index == -1) return false;

    final artifact = _artifacts[index];
    
    // Delete the local file
    try {
      final file = File(artifact.mediaPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Log error but continue with deletion
      debugPrint('Error deleting file: $e');
    }

    // Remove from list
    _artifacts.removeAt(index);
    await _persistArtifacts();
    _artifactController.add(List.unmodifiable(_artifacts));
    return true;
  }

  Future<void> saveSessionResult({
    required MemoryArtifact artifact,
    required String severity,
    required List<MemoryQuestion> questions,
    required List<int> responses,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final score = _aiService.scoreSession(
      questions: questions,
      selectedOptionIndexes: responses,
    );

    final categoryTotals = <MemoryCategory, int>{};
    for (final question in questions) {
      categoryTotals[question.category] = (categoryTotals[question.category] ?? 0) + 1;
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('memorySessions')
        .add({
      'artifactId': artifact.id,
      'severity': severity,
      'questions': questions.map((q) => q.toMap()).toList(),
      'responses': responses,
      'score': score.correctAnswers,
      'total': score.totalQuestions,
      'categoryBreakdown': score.categoryBreakdown.map(
        (key, value) => MapEntry(memoryCategoryToString(key), value),
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final scoreUpdate = <String, dynamic>{};
    categoryTotals.forEach((category, total) {
      final keyBase = 'memoryScores.${memoryCategoryToString(category)}';
      scoreUpdate['$keyBase.total'] = FieldValue.increment(total);
      final correct = score.categoryBreakdown[category] ?? 0;
      scoreUpdate['$keyBase.correct'] = FieldValue.increment(correct);
    });

    await _firestore.collection('users').doc(uid).set(scoreUpdate, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>> streamMemoryScores() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      return Map<String, dynamic>.from(doc.data()?['memoryScores'] ?? {});
    });
  }

  Stream<List<Map<String, dynamic>>> streamSessions() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('memorySessions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return <String, dynamic>{
                'id': doc.id,
                'score': data['score'] as int? ?? 0,
                'total': data['total'] as int? ?? 0,
                'severity': data['severity'] as String? ?? 'Moderate',
                'createdAt': data['createdAt'] as Timestamp?,
                'artifactId': data['artifactId'] as String? ?? '',
              };
            }).toList());
  }

  Future<String> fetchSeverityLevel() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'Moderate';
    final doc = await _firestore.collection('users').doc(uid).get();
    final stage = doc.data()?['stage'] as String?;
    if (stage == null) return 'Moderate';
    if (stage.toLowerCase().contains('early')) return 'Mild';
    if (stage.toLowerCase().contains('late')) return 'Severe';
    return stage;
  }

  bool _isVideo(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv');
  }

  Future<String> _saveFileLocally(XFile file) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(docsDir.path, 'memory_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    final extension = file.path.isNotEmpty ? p.extension(file.path) : p.extension(file.name);
    final filename = '${DateTime.now().millisecondsSinceEpoch}$extension';
    final destination = File(p.join(mediaDir.path, filename));
    final bytes = await file.readAsBytes();
    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  String get _storageKey {
    final uid = _lastUid ?? _auth.currentUser?.uid;
    if (uid == null) return _prefsKey;
    return '${_prefsKey}_$uid';
  }

  void dispose() {
    _authSubscription?.cancel();
    _artifactController.close();
  }
}

