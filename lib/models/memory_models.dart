enum MemoryCategory { people, places, events, objects, unknown }

MemoryCategory memoryCategoryFromString(String? value) {
  switch (value) {
    case 'people':
      return MemoryCategory.people;
    case 'places':
      return MemoryCategory.places;
    case 'events':
      return MemoryCategory.events;
    case 'objects':
      return MemoryCategory.objects;
    default:
      return MemoryCategory.unknown;
  }
}

String memoryCategoryToString(MemoryCategory category) {
  switch (category) {
    case MemoryCategory.people:
      return 'people';
    case MemoryCategory.places:
      return 'places';
    case MemoryCategory.events:
      return 'events';
    case MemoryCategory.objects:
      return 'objects';
    case MemoryCategory.unknown:
      return 'unknown';
  }
}

class MemoryArtifact {
  MemoryArtifact({
    required this.id,
    required this.mediaPath,
    required this.mediaType,
    required this.tags,
    required this.autoLabels,
    required this.primaryCategory,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String mediaPath;
  final String mediaType; // image | video
  final List<String> tags;
  final List<String> autoLabels;
  final MemoryCategory primaryCategory;
  final DateTime createdAt;
  final String? notes;

  factory MemoryArtifact.fromMap(Map<String, dynamic> data) {
    return MemoryArtifact(
      id: (data['id'] ?? '') as String,
      mediaPath: (data['mediaPath'] ?? '') as String,
      mediaType: (data['mediaType'] ?? 'image') as String,
      tags: List<String>.from(data['tags'] ?? const []),
      autoLabels: List<String>.from(data['autoLabels'] ?? const []),
      primaryCategory: memoryCategoryFromString(data['primaryCategory'] as String?),
      createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mediaPath': mediaPath,
      'mediaType': mediaType,
      'tags': tags,
      'autoLabels': autoLabels,
      'primaryCategory': memoryCategoryToString(primaryCategory),
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
    };
  }
}

class MemoryQuestion {
  MemoryQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.category,
    required this.level,
    required this.artifactId,
    this.hint,
  }) : assert(options.isNotEmpty && correctIndex >= 0 && correctIndex < options.length);

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final MemoryCategory category;
  final String level; // severe / moderate / mild
  final String artifactId; // Which memory artifact this question is about
  final String? hint;

  Map<String, dynamic> toMap() {
    return {
      'prompt': prompt,
      'options': options,
      'correctIndex': correctIndex,
      'category': memoryCategoryToString(category),
      'level': level,
      'artifactId': artifactId,
      'hint': hint,
    };
  }

  factory MemoryQuestion.fromMap(Map<String, dynamic> map) {
    return MemoryQuestion(
      prompt: map['prompt'] as String? ?? '',
      options: List<String>.from(map['options'] ?? const []),
      correctIndex: (map['correctIndex'] as num?)?.toInt() ?? 0,
      category: memoryCategoryFromString(map['category'] as String?),
      level: (map['level'] ?? 'moderate') as String,
      artifactId: map['artifactId'] as String? ?? '',
      hint: map['hint'] as String?,
    );
  }
}

class MemoryAnalysisResult {
  MemoryAnalysisResult({
    required this.labels,
    required this.primaryCategory,
    required this.summary,
  });

  final List<String> labels;
  final MemoryCategory primaryCategory;
  final String summary;
}

class MemorySessionScore {
  MemorySessionScore({
    required this.totalQuestions,
    required this.correctAnswers,
    required this.categoryBreakdown,
  });

  final int totalQuestions;
  final int correctAnswers;
  final Map<MemoryCategory, int> categoryBreakdown;
}

