import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/memory_models.dart';
import '../services/memory_ai_service.dart';
import '../services/memory_repository.dart';

class ReminiscenceTherapyScreen extends StatefulWidget {
  const ReminiscenceTherapyScreen({super.key});

  @override
  State<ReminiscenceTherapyScreen> createState() => _ReminiscenceTherapyScreenState();
}

class _ReminiscenceTherapyScreenState extends State<ReminiscenceTherapyScreen>
    with SingleTickerProviderStateMixin {
  final MemoryRepository _repository = MemoryRepository();
  final MemoryAIService _aiService = MemoryAIService();
  final ImagePicker _picker = ImagePicker();

  bool _initializing = true;
  bool _uploading = false;
  String _severity = 'Moderate';
  List<MemoryArtifact> _selectedArtifacts = []; // Changed to multi-select
  List<MemoryArtifact> _availableArtifacts = [];

  List<MemoryQuestion> _activeQuestions = [];
  List<int> _responses = [];
  int _activeIndex = 0;
  bool _sessionInProgress = false;
  bool _savingResults = false;
  MemorySessionScore? _sessionScore;
  bool get _canResetSession =>
      _sessionInProgress || _sessionScore != null || _activeQuestions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final severity = await _repository.fetchSeverityLevel();
    final artifacts = await _repository.fetchArtifacts();
    if (!mounted) return;
    setState(() {
      _severity = severity;
      _availableArtifacts = artifacts;
      _initializing = false;
    });
  }

  void _clearSessionState() {
    _sessionInProgress = false;
    _activeQuestions = [];
    _responses = [];
    _activeIndex = 0;
    _sessionScore = null;
    _savingResults = false;
  }

  void _resetSession() {
    setState(_clearSessionState);
  }

  @override
  void dispose() {
    _repository.dispose();
    _aiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reminiscence Therapy'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.collections), text: 'Library'),
              Tab(icon: Icon(Icons.question_answer), text: 'Adaptive Q&A'),
              Tab(icon: Icon(Icons.insights), text: 'Dashboard'),
            ],
          ),
        ),
        floatingActionButton: TabBarViewFAB(
          onAddMemory: _uploadMemory,
          onPickMemory: _showSelectedMemoriesSheet,
        ),
        body: TabBarView(
          children: [
            _buildLibraryTab(),
            _buildAdaptiveTab(),
            _buildDashboardTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryTab() {
    return StreamBuilder<List<MemoryArtifact>>(
      stream: _repository.streamArtifacts(),
      builder: (context, snapshot) {
        final artifacts = snapshot.data ?? [];
        _availableArtifacts = List<MemoryArtifact>.from(artifacts);
        if (artifacts.isEmpty) {
          return _emptyState(
            icon: Icons.landscape_rounded,
            text: 'No memories yet.\nUpload a photo or short clip to begin therapy.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: artifacts.length,
          itemBuilder: (context, index) {
            final artifact = artifacts[index];
            final isSelected = _selectedArtifacts.any((a) => a.id == artifact.id);
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? Colors.deepPurple : Colors.transparent,
                  width: isSelected ? 2 : 0,
                ),
              ),
              elevation: isSelected ? 4 : 1,
              margin: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: _artifactImagePreview(artifact),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: -8,
                          children: [
                            Chip(
                              label: Text(memoryCategoryToString(artifact.primaryCategory).toUpperCase()),
                              backgroundColor:
                                  Colors.deepPurple.withAlpha((0.1 * 255).round()),
                            ),
                            for (final tag in artifact.tags) Chip(label: Text(tag)),
                          ],
                        ),
                        if (artifact.notes?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            artifact.notes!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    if (!_selectedArtifacts.any((a) => a.id == artifact.id)) {
                                      _selectedArtifacts.add(artifact);
                                    }
                                  } else {
                                    _selectedArtifacts.removeWhere((a) => a.id == artifact.id);
                                  }
                                });
                              },
                            ),
                            Expanded(
                              child: Text(
                                isSelected ? 'Selected for Q&A' : 'Select for Q&A',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _confirmDeleteArtifact(artifact),
                              tooltip: 'Delete memory',
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () {
                                if (!_selectedArtifacts.any((a) => a.id == artifact.id)) {
                                  setState(() => _selectedArtifacts.add(artifact));
                                }
                                _startSession([artifact]);
                              },
                              icon: const Icon(Icons.flash_on),
                              label: const Text('Quick session'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAdaptiveTab() {
    if (_selectedArtifacts.isEmpty) {
      return _emptyState(
        icon: Icons.psychology_alt_outlined,
        text: 'Select memories from the Library tab to begin Q&A session.',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _severitySelector()),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _canResetSession ? _resetSession : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Selected: ${_selectedArtifacts.length} memory${_selectedArtifacts.length == 1 ? '' : 'ies'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_sessionInProgress)
            _questionCard()
          else
            Expanded(
              child: Center(
                child: FilledButton.icon(
                  onPressed: () => _startSession(_selectedArtifacts),
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 32),
                  label: const Text('Start adaptive session'),
                ),
              ),
            ),
          if (_sessionScore != null) _scoreBanner(_sessionScore!),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _repository.streamSessions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) {
          return _emptyState(
            icon: Icons.auto_graph,
            text: 'No sessions yet.\nRun a Q&A round to populate the dashboard.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Session History',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...sessions.map((session) => _sessionCard(session)),
          ],
        );
      },
    );
  }

  Widget _severitySelector() {
    const levels = ['Severe', 'Moderate', 'Mild'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Adaptive difficulty', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            for (final level in levels)
              ButtonSegment(
                value: level,
                label: Text(level),
              ),
          ],
          selected: {_severity},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _severity = selection.first);
          },
        ),
      ],
    );
  }

  Widget _questionCard() {
    if (_activeQuestions.isEmpty || _activeIndex >= _activeQuestions.length) {
      return const SizedBox.shrink();
    }

    final question = _activeQuestions[_activeIndex];
    final answeredIndex = _responses[_activeIndex];
    
    // Find the artifact for this question
    final artifact = _availableArtifacts.firstWhere(
      (a) => a.id == question.artifactId,
      orElse: () => _selectedArtifacts.firstWhere(
        (a) => a.id == question.artifactId,
        orElse: () => _availableArtifacts.isNotEmpty ? _availableArtifacts.first : throw StateError('No artifact found'),
      ),
    );
    
    final media = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _artifactImagePreview(artifact, height: 200),
    );

    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    media,
                    const SizedBox(height: 16),
                    Text(
                      'Question ${_activeIndex + 1} of ${_activeQuestions.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      question.prompt,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    ...List.generate(question.options.length, (optionIndex) {
                      final option = question.options[optionIndex];
                      final isSelected = answeredIndex == optionIndex;
                      final correct = question.correctIndex == optionIndex;
                      Color? color;
                      if (answeredIndex != -1) {
                        if (correct) {
                          color = Colors.green.withAlpha((0.2 * 255).round());
                        } else if (isSelected && !correct) {
                          color = Colors.red.withAlpha((0.2 * 255).round());
                        }
                      }
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: color,
                        child: ListTile(
                          title: Text(option),
                          trailing: isSelected ? const Icon(Icons.check_circle) : null,
                          onTap: answeredIndex == -1 ? () => _handleAnswer(optionIndex) : null,
                        ),
                      );
                    }),
                    if (answeredIndex != -1) ...[
                      const SizedBox(height: 16),
                // Show notes if answer is "No" or "Not sure"
                Builder(
                  builder: (context) {
                    final selectedOption = answeredIndex >= 0 && answeredIndex < question.options.length
                        ? question.options[answeredIndex].toLowerCase()
                        : '';
                    final isNegativeAnswer = selectedOption.contains('no') || 
                        selectedOption.contains('not sure') || 
                        selectedOption.contains('maybe') ||
                        (answeredIndex != question.correctIndex);
                    
                    if (isNegativeAnswer && artifact.notes?.isNotEmpty == true) {
                      return Column(
                        children: [
                          Card(
                            color: Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Memory Note:',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    artifact.notes!,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                    ],
                  ],
                ),
              ),
            ),
            if (answeredIndex != -1)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Text(question.correctIndex == answeredIndex ? 'Great job!' : "Let's try another."),
                    const Spacer(),
                    FilledButton(
                      onPressed: _activeIndex == _activeQuestions.length - 1
                          ? _completeSession
                          : () => setState(() => _activeIndex += 1),
                      child: Text(
                          _activeIndex == _activeQuestions.length - 1 ? 'Finish Session' : 'Next'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scoreBanner(MemorySessionScore score) {
    final percent = score.totalQuestions == 0
        ? 0
        : (score.correctAnswers / max(1, score.totalQuestions) * 100).round();
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session saved', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Accuracy: $percent% (${score.correctAnswers}/${score.totalQuestions})'),
          ],
        ),
      ),
    );
  }

  Widget _scoreCard(String category, int correct, int total) {
    final ratio = total == 0 ? 0.0 : correct / total;
    final color = Color.lerp(Colors.red, Colors.green, ratio.clamp(0, 1));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color?.withAlpha((0.2 * 255).round()),
          child: Text('${(ratio * 100).round()}%'),
        ),
        title: Text(category.toUpperCase()),
        subtitle: LinearProgressIndicator(
          value: ratio.isNaN ? 0 : ratio,
          color: color,
          backgroundColor: Colors.grey.shade200,
        ),
        trailing: Text('$correct / $total'),
      ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> session) {
    final score = session['score'] as int? ?? 0;
    final total = session['total'] as int? ?? 0;
    final severity = session['severity'] as String? ?? 'Moderate';
    final createdAt = session['createdAt'] as Timestamp?;
    
    final accuracy = total == 0 ? 0.0 : (score / total * 100);
    final color = Color.lerp(Colors.red, Colors.green, (accuracy / 100).clamp(0, 1)) ?? Colors.grey;
    
    String dateStr = 'Unknown date';
    if (createdAt != null) {
      final date = createdAt.toDate();
      dateStr = '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withAlpha((0.2 * 255).round()),
                  child: Text(
                    '${accuracy.round()}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(severity),
                  backgroundColor: Colors.deepPurple.withAlpha((0.1 * 255).round()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Accuracy',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${accuracy.toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Score',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$score / $total',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: accuracy / 100,
              color: color,
              backgroundColor: Colors.grey.shade200,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String text}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.deepPurple),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadMemory() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminiscence uploads are only available on mobile builds.')),
      );
      return;
    }
    if (_uploading) return;
    final source = await showModalBottomSheet<_MemoryUploadSource>(
      context: context,
      builder: (context) => const _UploadPickerSheet(),
    );
    if (!mounted) return;
    if (source == null) return;

    XFile? picked;
    if (source == _MemoryUploadSource.photo) {
      picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    } else if (source == _MemoryUploadSource.video) {
      picked = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 45));
    }
    if (picked == null) return;
    if (!mounted) return;

    final tagController = TextEditingController();
    final notesController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Describe this memory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tagController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Short note (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm != true) return;

    final tags = tagController.text
        .split(',')
        .map((e) => e.trim())
        .where((element) => element.isNotEmpty)
        .toList();

    setState(() => _uploading = true);
    try {
      final artifact = await _repository.uploadArtifact(
        file: picked,
        tags: tags,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      );
      if (!mounted) return;
      if (artifact != null) {
        setState(() {
          if (!_selectedArtifacts.any((a) => a.id == artifact.id)) {
            _selectedArtifacts.add(artifact);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memory uploaded. Select it for Q&A session!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDeleteArtifact(MemoryArtifact artifact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Memory?'),
        content: Text(
          'Are you sure you want to delete this memory? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final deleted = await _repository.deleteArtifact(artifact.id);
      if (!mounted) return;
      
      if (deleted) {
        // Remove from selected artifacts if it was selected
        setState(() {
          _selectedArtifacts.removeWhere((a) => a.id == artifact.id);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Memory deleted successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete memory')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting memory: $e')),
      );
    }
  }


  Future<void> _showSelectedMemoriesSheet() async {
    if (_availableArtifacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload a memory first.')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('Select memories for Q&A'),
                    subtitle: Text('Check multiple memories to include in session'),
                  ),
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final artifact in _availableArtifacts)
                          CheckboxListTile(
                            value: _selectedArtifacts.any((a) => a.id == artifact.id),
                            onChanged: (checked) {
                              setSheetState(() {
                                if (checked == true) {
                                  if (!_selectedArtifacts.any((a) => a.id == artifact.id)) {
                                    _selectedArtifacts.add(artifact);
                                  }
                                } else {
                                  _selectedArtifacts.removeWhere((a) => a.id == artifact.id);
                                }
                              });
                              setState(() {}); // Update main state
                            },
                            secondary: SizedBox(
                              width: 56,
                              height: 56,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _artifactImagePreview(artifact, height: 56),
                              ),
                            ),
                            title: Text(
                              artifact.tags.isNotEmpty
                                  ? artifact.tags.first
                                  : (artifact.notes?.isNotEmpty == true ? artifact.notes! : 'Memory ${artifact.id}'),
                            ),
                            subtitle: artifact.notes?.isNotEmpty == true ? Text(artifact.notes!) : null,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startSession(List<MemoryArtifact> artifacts) async {
    if (artifacts.isEmpty) return;
    setState(() {
      _sessionInProgress = true;
      _activeQuestions = [];
      _responses = [];
      _activeIndex = 0;
      _sessionScore = null;
    });

    final questions = await _aiService.buildAdaptiveQuestions(
      artifacts: artifacts,
      severityLevel: _severity,
    );
    if (!mounted) return;
    if (questions.isEmpty) {
      setState(() {
        _sessionInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not build questions. Check API key or try again.')),
      );
      return;
    }
    setState(() {
      _activeQuestions = questions;
      _responses = List.filled(questions.length, -1);
    });
  }

  void _handleAnswer(int optionIndex) {
    setState(() {
      _responses[_activeIndex] = optionIndex;
    });
  }

  Future<void> _completeSession() async {
    if (_selectedArtifacts.isEmpty || _savingResults) return;
    setState(() => _savingResults = true);
    
    // Save session for each artifact that had questions
    final artifactIds = _activeQuestions.map((q) => q.artifactId).toSet();
    for (final artifactId in artifactIds) {
      final artifact = _selectedArtifacts.firstWhere(
        (a) => a.id == artifactId,
        orElse: () => _availableArtifacts.firstWhere((a) => a.id == artifactId),
      );
      final artifactQuestions = _activeQuestions.where((q) => q.artifactId == artifactId).toList();
      final artifactResponses = <int>[];
      for (int i = 0; i < _activeQuestions.length; i++) {
        if (_activeQuestions[i].artifactId == artifactId) {
          artifactResponses.add(_responses[i]);
        }
      }
      
      await _repository.saveSessionResult(
        artifact: artifact,
        severity: _severity,
        questions: artifactQuestions,
        responses: artifactResponses,
      );
    }
    
    final score = _aiService.scoreSession(
      questions: _activeQuestions,
      selectedOptionIndexes: _responses,
    );
    if (!mounted) return;
    setState(() {
      _sessionInProgress = false;
      _savingResults = false;
      _sessionScore = score;
      _activeQuestions = [];
      _responses = [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session stored. Dashboard updated.')),
    );
  }
}

Widget _artifactImagePreview(MemoryArtifact artifact, {double height = 180}) {
  if (artifact.mediaType == 'video') {
    return Container(
      color: Colors.black87,
      height: height,
      width: double.infinity,
      child: const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white, size: 56),
      ),
    );
  }
  if (kIsWeb) {
    return Container(
      color: Colors.grey.shade200,
      height: height,
      child: const Center(child: Icon(Icons.image_not_supported)),
    );
  }
  final file = File(artifact.mediaPath);
  if (!file.existsSync()) {
    return Container(
      color: Colors.grey.shade200,
      height: height,
      child: const Center(child: Icon(Icons.broken_image)),
    );
  }
  return Image.file(
    file,
    height: height,
    width: double.infinity,
    fit: BoxFit.cover,
  );
}

class TabBarViewFAB extends StatelessWidget {
  const TabBarViewFAB({super.key, required this.onAddMemory, required this.onPickMemory});

  final VoidCallback onAddMemory;
  final VoidCallback onPickMemory;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final animation = controller.animation;
    if (animation == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final index = controller.index;
        if (index != 0) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.extended(
              heroTag: 'selectedMemoriesFab',
              onPressed: onPickMemory,
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: const Text('Selected memories'),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.extended(
              heroTag: 'uploadMemoryFab',
              onPressed: onAddMemory,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Upload memory'),
            ),
          ],
        );
      },
    );
  }
}

enum _MemoryUploadSource { photo, video }

class _UploadPickerSheet extends StatelessWidget {
  const _UploadPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Photo from gallery'),
            onTap: () => Navigator.of(context).pop(_MemoryUploadSource.photo),
          ),
          ListTile(
            leading: const Icon(Icons.video_library),
            title: const Text('Video (≤45s)'),
            onTap: () => Navigator.of(context).pop(_MemoryUploadSource.video),
          ),
        ],
      ),
    );
  }
}

