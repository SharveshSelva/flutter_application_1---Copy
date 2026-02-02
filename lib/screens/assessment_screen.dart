import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({super.key});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  final List<String> _questions = const [
    'How often does the person forget recent events or conversations, even after reminders?',
    'How often does the person forget familiar names or faces of close family and friends?',
    'Does the person become confused about where they are or what day/time it is?',
    'How frequently does the person wander or become lost in familiar places?',
    'How often does the person struggle to find the right word or follow a conversation?',
    'Is the person still able to carry on a meaningful conversation?',
    'How much assistance is needed with daily activities (dressing, eating, hygiene)?',
    'Does the person show difficulty choosing clothing or using familiar household items?',
    'Have you noticed increased mood swings, suspicion, or repetitive behaviors?',
    'Does the person appear withdrawn, unresponsive, or unable to express needs?',
  ];

  final Map<int, int> _answers = {};
  int? _totalScore;
  String? _stage;

  Future<void> _calculate() async {
    if (_answers.length != _questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions')),
      );
      return;
    }
    final total = _answers.values.fold<int>(0, (sum, v) => sum + v);
    String stage;
    if (total <= 8) {
      stage = 'Early Stage (Mild)';
    } else if (total <= 20) {
      stage = 'Middle Stage (Moderate)';
    } else {
      stage = 'Late Stage (Severe)';
    }
    setState(() {
      _totalScore = total;
      _stage = stage;
    });

    _saveAssessment(total, stage);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assessment Result'),
        content: Text('Score: $total / 30\nStage: $stage'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final bool returnToLogin = args?['returnToLogin'] == true;
    final Map<String, dynamic>? userData = args?['userData'] as Map<String, dynamic>?;
    if (returnToLogin) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false, arguments: userData);
    }
  }

  Future<void> _saveAssessment(int total, String stage) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final users = FirebaseFirestore.instance.collection('users');
      await users.doc(user.uid).set({
        'stage': stage,
        'lastAssessmentScore': total,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save assessment: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final bool returnToLogin = args?['returnToLogin'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alzheimer\'s Severity Assessment'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q${index + 1}. ${_questions[index]}',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _optionChip(index, 0, 'Never'),
                            _optionChip(index, 1, 'Sometimes'),
                            _optionChip(index, 2, 'Often'),
                            _optionChip(index, 3, 'Always'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_totalScore != null && _stage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Score: $_totalScore / 30'),
                  Text(_stage!),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _calculate,
                child: const Text('Calculate Score'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionChip(int questionIndex, int value, String label) {
    final selected = _answers[questionIndex] == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _answers[questionIndex] = value),
    );
  }
}


