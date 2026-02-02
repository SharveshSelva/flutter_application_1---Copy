import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

class TaskDetailsPage extends StatefulWidget {
  final String title;
  final String? time; // optional time string like 08:00 AM
  final String? imageUrl; // optional photo url

  const TaskDetailsPage({super.key, required this.title, this.time, this.imageUrl});

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage> {
  bool _done = false;
  bool _canAddMedia = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserStage();
  }

  Future<void> _loadUserStage() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _prefsLoaded = true;
        });
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final stage = (doc.data()?['stage'] as String?)?.toLowerCase() ?? '';
      final isMild = stage.contains('early') || stage.contains('mild');
      setState(() {
        _canAddMedia = isMild;
        _prefsLoaded = true;
      });
    } catch (_) {
      setState(() {
        _prefsLoaded = true;
      });
    }
  }

  void _showReminderDialog() {
  DateTime selectedTime = DateTime.now().add(const Duration(minutes: 1)); // Changed to 1 minute
  
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Reminder'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Are you sure you want to add remainder?'),
                const SizedBox(height: 16),
                const Text('Select reminder time:'),
                const SizedBox(height: 8),
                // Quick test buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        selectedTime = DateTime.now().add(const Duration(seconds: 30));
                        setState(() {});
                      },
                      child: const Text('30 sec'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        selectedTime = DateTime.now().add(const Duration(minutes: 1));
                        setState(() {});
                      },
                      child: const Text('1 min'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedTime),
                    );
                    if (picked != null) {
                      final now = DateTime.now();
                      selectedTime = DateTime(
                        now.year,
                        now.month,
                        now.day,
                        picked.hour,
                        picked.minute,
                      );
                      if (selectedTime.isBefore(now)) {
                        selectedTime = selectedTime.add(const Duration(days: 1));
                      }
                      setState(() {});
                    }
                  },
                  child: Text(
                    '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _scheduleReminder(selectedTime);
                },
                child: const Text('Set Reminder'),
              ),
            ],
          );
        },
      );
    },
  );
}

  void _scheduleReminder(DateTime reminderTime) async {
     print('--- [TASK DETAILS] Calling scheduleTaskReminder with time: $reminderTime');
  try {
    final hasPermission = await NotificationService.requestPermissions();
    
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable notification and alarm permissions in Settings'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    await NotificationService.scheduleTaskReminder(
      taskTitle: widget.title,
      reminderTime: reminderTime,
    );
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.alarm, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reminder set for ${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  } catch (e) {
    debugPrint('❌ Error scheduling reminder: $e');
    
    if (!mounted) return;
    
    String errorMessage = 'Failed to set reminder';
    if (e.toString().contains('past')) {
      errorMessage = 'Cannot set reminder in the past. Please choose a future time.';
    } else if (e.toString().contains('not initialized')) {
      errorMessage = 'Notification service not ready. Please restart the app.';
    } else {
      errorMessage = 'Failed to set reminder. Please check app permissions.';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pastel = theme.colorScheme.surfaceVariant.withOpacity(0.3);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: pastel,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                    child: const Icon(Icons.task_rounded, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (widget.time != null) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.access_time, size: 18),
                            const SizedBox(width: 6),
                            Text(widget.time!),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _showReminderDialog,
                    child: Icon(
                      Icons.notifications,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(widget.imageUrl!, height: 160, fit: BoxFit.cover),
            ),
          if (widget.imageUrl != null) const SizedBox(height: 16),
          if (_prefsLoaded && _canAddMedia)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Voice note feature not implemented')),
                      );
                    },
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text('Add voice note'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Image attachment feature not implemented')),
                      );
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Add image'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () {
                setState(() => _done = true);
                Navigator.of(context).pop(true);
              },
              icon: const Icon(Icons.check_circle_rounded, size: 24),
              label: Text(_done ? 'Completed' : 'Mark as Done', style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}






