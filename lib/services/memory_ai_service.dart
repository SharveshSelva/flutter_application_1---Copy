import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/memory_models.dart';

const String _envOpenAIApiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

class MemoryAIService {
  MemoryAIService({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _explicitKey = apiKey;

  final http.Client _client;
  final String? _explicitKey;

  Future<MemoryAnalysisResult> analyzeArtifact({
    required XFile file,
    List<String> manualTags = const [],
  }) async {
    if (kIsWeb || file.path.isEmpty) {
      return MemoryAnalysisResult(
        labels: manualTags,
        primaryCategory: _categoryFromHints(manualTags),
        summary: 'Manual tags only (web upload).',
      );
    }

    final lowerPath = file.path.toLowerCase();
    if (lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.mov') ||
        lowerPath.endsWith('.avi') ||
        lowerPath.endsWith('.mkv')) {
      return MemoryAnalysisResult(
        labels: manualTags,
        primaryCategory: _categoryFromHints(manualTags),
        summary: 'Video uploaded. Using caregiver tags for context.',
      );
    }

    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.55),
    );

    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final labels = await labeler.processImage(inputImage);
      final detected = labels.map((e) => e.label).toList();
      final allLabels = {...detected, ...manualTags}.toList();
      final category = _categoryFromHints(allLabels);

      return MemoryAnalysisResult(
        labels: allLabels,
        primaryCategory: category,
        summary: 'Detected: ${allLabels.join(', ')}',
      );
    } catch (_) {
      final category = _categoryFromHints(manualTags);
      return MemoryAnalysisResult(
        labels: manualTags,
        primaryCategory: category,
        summary: 'Vision model unavailable. Using caregiver tags.',
      );
    } finally {
      labeler.close();
    }
  }

  Future<List<MemoryQuestion>> buildAdaptiveQuestions({
    required List<MemoryArtifact> artifacts,
    required String severityLevel,
  }) async {
    final key = _resolveKey();
    if (key.isEmpty || artifacts.isEmpty) {
      return _fallbackQuestions(artifacts: artifacts, severity: severityLevel);
    }

    // Generate questions for each artifact
    final allQuestions = <MemoryQuestion>[];
    for (final artifact in artifacts) {
      final prompt = _promptForArtifact(artifact, severityLevel);
    try {
      final response = await _client.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $key',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'temperature': 0.4,
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'memory_questions',
              'schema': {
                'type': 'object',
                'properties': {
                  'questions': {
                    'type': 'array',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'prompt': {'type': 'string'},
                        'options': {
                          'type': 'array',
                          'items': {'type': 'string'},
                          'minItems': 2,
                        },
                        'correctIndex': {'type': 'integer'},
                        'category': {'type': 'string'},
                        'level': {'type': 'string'},
                        'hint': {'type': 'string'},
                      },
                      'required': ['prompt', 'options', 'correctIndex', 'category', 'level'],
                    },
                    'minItems': 3,
                    'maxItems': 5,
                  },
                },
                'required': ['questions'],
              },
            },
          },
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a cognitive therapist specializing in reminiscence therapy. Keep tone encouraging and simple.',
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
        }),
      );

      if (response.statusCode != 200) {
        allQuestions.addAll(_fallbackQuestions(artifacts: [artifact], severity: severityLevel));
        continue;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['choices'][0]['message']['content'];
      final parsed = content is String ? jsonDecode(content) : content;

      final questionsRaw = parsed['questions'] as List<dynamic>? ?? const [];
      if (questionsRaw.isEmpty) {
        allQuestions.addAll(_fallbackQuestions(artifacts: [artifact], severity: severityLevel));
      } else {
        allQuestions.addAll(questionsRaw
            .map((q) => MemoryQuestion.fromMap({
                  'prompt': q['prompt'],
                  'options': q['options'],
                  'correctIndex': q['correctIndex'],
                  'category': q['category'],
                  'level': q['level'],
                  'artifactId': artifact.id,
                  'hint': q['hint'],
                }))
            .toList());
      }
    } catch (_) {
      allQuestions.addAll(_fallbackQuestions(artifacts: [artifact], severity: severityLevel));
    }
    }
    return allQuestions;
  }

  MemorySessionScore scoreSession({
    required List<MemoryQuestion> questions,
    required List<int> selectedOptionIndexes,
  }) {
    int correct = 0;
    final breakdown = <MemoryCategory, int>{};

    for (var i = 0; i < questions.length; i++) {
      final question = questions[i];
      final selected = i < selectedOptionIndexes.length ? selectedOptionIndexes[i] : -1;
      final isCorrect = selected == question.correctIndex;
      if (isCorrect) correct += 1;
      if (isCorrect) {
        breakdown[question.category] = (breakdown[question.category] ?? 0) + 1;
      }
    }

    return MemorySessionScore(
      totalQuestions: questions.length,
      correctAnswers: correct,
      categoryBreakdown: breakdown,
    );
  }

  void dispose() {
    _client.close();
  }

  List<MemoryQuestion> _fallbackQuestions({
    required List<MemoryArtifact> artifacts,
    required String severity,
  }) {
    final allQuestions = <MemoryQuestion>[];
    for (final artifact in artifacts) {
      final category = artifact.primaryCategory;
      final basePrompt = _basePromptForCategory(category, artifact);
      final mainTag = artifact.tags.isNotEmpty ? artifact.tags.first : 'this memory';

      final yesNoPrompt = MemoryQuestion(
        prompt: 'Do you remember $mainTag?',
        options: const ['Yes', 'No', 'Not sure'],
        correctIndex: 0,
        category: category,
        level: severity.toLowerCase().contains('severe') ? 'severe' : 'moderate',
        artifactId: artifact.id,
        hint: basePrompt,
      );

      allQuestions.add(yesNoPrompt);
    }
    return allQuestions;
  }

  String _promptForArtifact(MemoryArtifact artifact, String severity) {
    final mainTag = artifact.tags.isNotEmpty ? artifact.tags.first : 'this memory';
    return '''
Create simple reminiscence therapy questions focused on recognition.
Severity level: $severity
Main tag: $mainTag
All tags: ${artifact.tags.join(', ')}
Auto labels: ${artifact.autoLabels.join(', ')}
Primary category: ${memoryCategoryToString(artifact.primaryCategory)}

Rules:
- Generate ONLY simple "Do you remember this?" style questions.
- Focus on recognition, NOT complex questions like "Where did this happen?" or "What do you think about this?"
- Keep questions short and encouraging.
- Provide 1-2 simple questions per memory.
- Options should be: ["Yes", "No", "Not sure"] or ["I remember", "I don't remember", "Maybe"]
- The correct answer should be "Yes" or "I remember" (index 0) if the patient should recognize it.
- Provide a short hint for caregivers.
''';
  }

  MemoryCategory _categoryFromHints(List<String> hints) {
    final lower = hints.map((t) => t.toLowerCase()).toList();
    if (lower.any((val) => val.contains('mom') || val.contains('dad') || val.contains('person') || val.contains('friend'))) {
      return MemoryCategory.people;
    }
    if (lower.any((val) => val.contains('home') || val.contains('house') || val.contains('beach') || val.contains('park') || val.contains('place'))) {
      return MemoryCategory.places;
    }
    if (lower.any((val) => val.contains('birthday') || val.contains('wedding') || val.contains('party') || val.contains('anniversary'))) {
      return MemoryCategory.events;
    }
    if (lower.any((val) => val.contains('car') || val.contains('book') || val.contains('uniform') || val.contains('object'))) {
      return MemoryCategory.objects;
    }
    return MemoryCategory.unknown;
  }

  String _categoryLabel(MemoryCategory category) {
    switch (category) {
      case MemoryCategory.people:
        return 'person';
      case MemoryCategory.places:
        return 'place';
      case MemoryCategory.events:
        return 'event';
      case MemoryCategory.objects:
        return 'object';
      case MemoryCategory.unknown:
        return 'memory';
    }
  }

  String _basePromptForCategory(MemoryCategory category, MemoryArtifact artifact) {
    final labels = [...artifact.tags, ...artifact.autoLabels].join(', ');
    return 'Clues: $labels';
  }

  String _resolveKey() {
    final key = _explicitKey;
    if (key != null && key.isNotEmpty) return key;
    return _envOpenAIApiKey;
  }
}

