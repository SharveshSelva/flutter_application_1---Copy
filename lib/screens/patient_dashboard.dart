import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}   

class _PatientDashboardState extends State<PatientDashboard> {
  int _selectedIndex = 0;
  String? _stageTag;
  final Color _bg = const Color(0xFFEFF4FA); // softer pastel background for contrast
  Map<String, dynamic>? _cachedUserData;
  List<Map<String, dynamic>> _cachedTasks = [];
  bool _userDataLoaded = false;
  bool _tasksLoaded = false;

  final List<String> _tasks = [
    'Take morning medication',
    '30 minutes walk',
    'Record blood pressure',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
    _loadAllData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Check if we have user data passed from registration
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && _cachedUserData == null) {
      _cachedUserData = args;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        // no title as requested; keep logout action
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
          ),
        ],
      ),
      body: Container(
        color: _getBackgroundColor(),
        child: _buildBody(),
      ),
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _showAddTaskDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Task'),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.grey[200],
        selectedItemColor: Colors.purple,
        unselectedItemColor: Colors.purple[300],
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded, color: Colors.purple), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded, color: Colors.purple), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.alarm_rounded, color: Colors.purple), label: 'Reminders'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded, color: Colors.purple), label: 'Profile'),
        ],
      ),
    );
  }

  Future<void> _loadAllData() async {
    // Load user data
    if (!_userDataLoaded) {
      _cachedUserData = await _fetchUserDataFromFirestore();
      _userDataLoaded = true;
    }
    
    // Load tasks data
    if (!_tasksLoaded) {
      _cachedTasks = await _fetchTasksFromFirestore();
      _tasksLoaded = true;
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, dynamic>?> _fetchUserDataFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data();
      }
    } catch (e) {
      // Return null on error
    }
    
    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchTasksFromFirestore() async {
    final uid = _uid;
    if (uid == null) return [];
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .orderBy('time', descending: false)
          .get();
      
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Map<String, dynamic>? get _userData {
    return _cachedUserData;
  }

  List<Map<String, dynamic>> get _allTasks {
    return _cachedTasks;
  }

  List<Map<String, dynamic>> get _pendingTasks {
    return _cachedTasks.where((task) => !(task['done'] ?? false)).toList();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _tasksStream({bool includeDone = true}) {
    final uid = _uid;
    if (uid == null) {
      return const Stream.empty();
    }
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .orderBy('time', descending: false);
    if (!includeDone) {
      q = q.where('done', isEqualTo: false);
    }
    return q.snapshots();
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildHome();
      case 1:
        return _buildTasks();
      case 2:
        return _buildReminders();
      case 3:
        return _buildProfile();
      default:
        return _buildHome();
    }
  }

  Widget _buildGreeting() {
    final data = _userData;
    final name = (data?['fullName'] as String?)?.trim();
    final first = (name == null || name.isEmpty) ? 'there' : name.split(' ').first;
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Good morning, $first', style: TextStyle(fontSize: _scalableFont(28), fontWeight: FontWeight.bold, color: _getTextColor())),
        const SizedBox(height: 6),
        Text(dateStr, style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor().withOpacity(0.7))),
      ],
    );
  }

  Widget _buildNextTaskCard() {
    final pendingTasks = _pendingTasks;
    if (pendingTasks.isEmpty) {
      return Row(
        children: [
          Icon(Icons.schedule_rounded, size: 28, color: _getPrimaryColor()),
          const SizedBox(width: 8),
          Expanded(child: Text('Next: No tasks', style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor()))),
        ],
      );
    }
    
    final task = pendingTasks.first;
    final title = (task['title'] ?? '') as String;
    final ts = task['time'];
    String timeStr = '';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      timeStr = '$h:$m $ampm';
    }
    
    return Row(
      children: [
        Icon(Icons.schedule_rounded, size: 28, color: _getPrimaryColor()),
        const SizedBox(width: 8),
        Expanded(child: Text('Next: $title $timeStr', style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor()))),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        title, 
        style: TextStyle(
          fontSize: _scalableFont(20), 
          fontWeight: FontWeight.w700,
          color: _getTextColor(),
        ),
      ),
    );
  }

  Widget _buildHome() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildGreeting(),
            ),
            const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _roundedCard(
                  child: Row(
                    children: [
                      Icon(Icons.wb_sunny_rounded, size: 28, color: _getPrimaryColor()),
                      const SizedBox(width: 8),
                      Text('Weather: Sunny 27°C', style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor())),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
            Expanded(
                child: _roundedCard(
                  child: _buildNextTaskCard(),
                ),
              ),
            ],
          ),
        ),
        _sectionTitle("Today's Tasks"),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildTasksList(),
        ),
        _sectionTitle('Memory Therapy'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _reminiscenceCard(),
        ),
      ],
    );
  }

  Widget _buildTasksList() {
    if (_allTasks.isEmpty) {
      return _emptyTasksCard();
    }
    
    return Column(
      children: [
        for (final task in _allTasks) _taskTile(task['id'], task),
      ],
    );
  }

  Widget _buildTasks() {
    if (_allTasks.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [_emptyTasksCard()]);
    }
    
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _allTasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = _allTasks[index];
        return _taskTile(task['id'], task);
      },
    );
  }

  Widget _emptyTasksCard() {
    return _roundedCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.inbox_rounded, size: 28, color: _getPrimaryColor()),
            const SizedBox(width: 10),
            Expanded(child: Text('No tasks yet. Tasks you add will show here.', style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor()))),
          ],
        ),
      ),
    );
  }

  Widget _buildReminders() {
    final pendingTasks = _pendingTasks;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: (pendingTasks.isEmpty ? 1 : pendingTasks.length) + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _roundedCard(
            child: ListTile(
              leading: Icon(Icons.psychology_rounded, color: _getPrimaryColor()),
              title: Text('Digitized Reminiscence', style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor())),
              subtitle: Text('AI-guided memory questions', style: TextStyle(color: _getTextColor().withOpacity(0.7))),
              trailing: OutlinedButton(
                onPressed: () => Navigator.of(context).pushNamed('/reminiscence'),
                child: const Text('Open'),
              ),
            ),
          );
        }
        if (pendingTasks.isEmpty) {
          return _roundedCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.alarm_rounded, size: 28, color: _getPrimaryColor()),
                  const SizedBox(width: 10),
                  Expanded(child: Text('No reminders yet. Upcoming tasks will appear in a timeline.', style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor()))),
                ],
              ),
            ),
          );
        }
        final task = pendingTasks[index - 1];
        final id = task['id'];
        final title = (task['title'] ?? '') as String;
        final ts = task['time'];
        String timeStr = '';
        if (ts is Timestamp) {
          final dt = ts.toDate();
          final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
          final m = dt.minute.toString().padLeft(2, '0');
          final ampm = dt.hour >= 12 ? 'PM' : 'AM';
          timeStr = '$h:$m $ampm';
        }
        return _roundedCard(
          child: ListTile(
            leading: Icon(Icons.notifications_active_rounded, color: _getPrimaryColor()),
            title: Text(title, style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor())),
            subtitle: Text(timeStr, style: TextStyle(fontSize: _scalableFont(14), color: _getTextColor().withOpacity(0.7))),
            trailing: Wrap(
              spacing: 8,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded),
                  onPressed: () => _markDone(id, true),
                  tooltip: 'Done',
                ),
                IconButton(
                  icon: const Icon(Icons.snooze_rounded),
                  onPressed: () => _remindLater(id, minutes: 15),
                  tooltip: 'Remind later',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // caregiver section removed per request

  Widget _buildProfile() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Profile'),
        _roundedCard(
          child: _buildProfileContent(),
        ),
      ],
    );
  }

  Widget _buildProfileContent() {
    final data = _userData ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _profileRow('Name', (data['fullName'] ?? 'Not set').toString()),
        _profileRow('Age / DOB', (data['dateOfBirth'] ?? 'Not set').toString()),
        _profileRow('Stage', (data['stage'] ?? 'Unknown').toString()),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Accessibility', 
          style: TextStyle(
            fontSize: _scalableFont(18), 
            fontWeight: FontWeight.w600,
            color: _getTextColor()
          )
        ),
        const SizedBox(height: 8),
        _accessibilityControls(),
      ],
    );
  }

  Widget _roundedCard({required Widget child}) {
    return Card(
      color: _getCardColor(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: _highContrast ? 3 : 1,
      child: child,
    );
  }

  Widget _reminiscenceCard() {
    return _roundedCard(
      child: ListTile(
        leading: Icon(Icons.psychology_alt_rounded, color: _getPrimaryColor(), size: 32),
        title: Text(
          'Digitized Reminiscence Therapy',
          style: TextStyle(fontSize: _scalableFont(18), fontWeight: FontWeight.w600, color: _getTextColor()),
        ),
        subtitle: Text(
          'Upload memories, let AI ask adaptive questions, and track strengths.',
          style: TextStyle(color: _getTextColor().withOpacity(0.7)),
        ),
        trailing: ElevatedButton(
          onPressed: () => Navigator.of(context).pushNamed('/reminiscence'),
          child: const Text('Open'),
        ),
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140, 
            child: Text(
              label, 
              style: TextStyle(
                fontSize: _scalableFont(16), 
                color: _highContrast ? Colors.white : Colors.grey
              )
            )
          ),
          Expanded(
            child: Text(
              value, 
              style: TextStyle(
                fontSize: _scalableFont(16), 
                color: _getTextColor()
              )
            )
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Switch(value: value, onChanged: (_) {}),
        ],
      ),
    );
  }

  double _scalableFont(double base) {
    // Apply user-controlled font scaling
    return base * _fontScale;
  }

  final bool _highContrast = false;
  double _fontScale = 1.0;

  // Helper methods for contrast-aware colors
  Color _getContrastColor(Color normalColor, Color highContrastColor) {
    return _highContrast ? highContrastColor : normalColor;
  }

  Color _getBackgroundColor() {
    return _getContrastColor(_bg, Colors.black);
  }

  Color _getCardColor() {
    return _getContrastColor(Theme.of(context).colorScheme.surface, Colors.white);
  }

  Color _getTextColor() {
    return _getContrastColor(Theme.of(context).colorScheme.onSurface, Colors.white);
  }

  Color _getPrimaryColor() {
    return _getContrastColor(Theme.of(context).colorScheme.primary, Colors.yellow);
  }

  Future<void> _loadUserPreferences() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      final savedScale = (data?['fontScale'] as num?)?.toDouble();
      if (savedScale != null) {
        setState(() {
          _fontScale = savedScale.clamp(1.0, 1.6);
        });
      }
    } catch (_) {
      // ignore errors; fall back to default
    }
  }

  Future<void> _saveFontScale(double scale) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'fontScale': scale.clamp(1.0, 1.6)}, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  Widget _accessibilityControls() {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'Font size', 
              style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor())
            ),
            Expanded(
              child: Slider(
                min: 1.0,
                max: 1.6,
                value: _fontScale,
                onChanged: (v) => setState(() => _fontScale = v),
                onChangeEnd: (v) => _saveFontScale(v),
              ),
            ),
            Text(
              '${(_fontScale * 100).round()}%', 
              style: TextStyle(fontSize: _scalableFont(16), color: _getTextColor())
            ),
          ],
        ),
      ],
    );
  }

  Widget _taskTile(String id, Map<String, dynamic> data) {
    final title = (data['title'] ?? '') as String;
    final done = (data['done'] ?? false) as bool;
    final ts = data['time'];
    String timeStr = '';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      timeStr = '$h:$m $ampm';
    }
    final theme = Theme.of(context);
    return _roundedCard(
      child: ListTile(
        leading: Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, 
          color: done ? (_highContrast ? Colors.lightGreen : Colors.green) : _getPrimaryColor()
        ),
        title: Text(
          title, 
          style: TextStyle(
            fontSize: _scalableFont(16),
            color: _getTextColor(),
            decoration: done ? TextDecoration.lineThrough : TextDecoration.none
          )
        ),
        subtitle: timeStr.isEmpty ? null : Text(
          timeStr, 
          style: TextStyle(
            fontSize: _scalableFont(14), 
            color: _getTextColor().withOpacity(0.7)
          )
        ),
        onTap: () async {
          final result = await Navigator.of(context).pushNamed('/taskDetails', arguments: {
            'title': title,
            'time': timeStr,
          });
          if (result == true) {
            _markDone(id, true);
          }
        },
        trailing: IconButton(
          icon: Icon(Icons.check_rounded, color: _getPrimaryColor()),
          onPressed: () => _markDone(id, !done),
        ),
      ),
    );
  }

  Future<void> _markDone(String id, bool done) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id).set({
      'done': done,
    }, SetOptions(merge: true));

    // Keep local cache in sync for instant UI updates
    final index = _cachedTasks.indexWhere((t) => t['id'] == id);
    if (index >= 0) {
      setState(() {
        _cachedTasks[index] = {
          ..._cachedTasks[index],
          'done': done,
        };
      });
    }
  }

  Future<void> _remindLater(String id, {int minutes = 15}) async {
    final uid = _uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').doc(id);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final ts = data['time'];
    DateTime when = DateTime.now();
    if (ts is Timestamp) when = ts.toDate();
    when = when.add(Duration(minutes: minutes));
    await ref.set({'time': Timestamp.fromDate(when)}, SetOptions(merge: true));

    // Update local cache
    final index = _cachedTasks.indexWhere((t) => t['id'] == id);
    if (index >= 0) {
      setState(() {
        _cachedTasks[index] = {
          ..._cachedTasks[index],
          'time': Timestamp.fromDate(when),
        };
        _sortCachedTasks();
      });
    }
  }

  Future<void> _showAddTaskDialog() async {
    final titleCtrl = TextEditingController();
    DateTime when = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.access_time),
                  const SizedBox(width: 8),
                  Text('${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(when),
                      );
                      if (picked != null) {
                        setState(() {
                          when = DateTime(when.year, when.month, when.day, picked.hour, picked.minute);
                        });
                      }
                    },
                    child: const Text('Pick time'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
          ],
        );
      },
    );
    if (ok == true) {
      final uid = _uid;
      if (uid == null) return;
      final title = titleCtrl.text.trim().isEmpty ? 'Untitled task' : titleCtrl.text.trim();
      final timeTs = Timestamp.fromDate(when);
      final ref = await FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks').add({
        'title': title,
        'time': timeTs,
        'done': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Insert into local cache for immediate display
      setState(() {
        _cachedTasks.add({
          'id': ref.id,
          'title': title,
          'time': timeTs,
          'done': false,
        });
        _tasksLoaded = true;
        _sortCachedTasks();
      });
    }
  }

  void _sortCachedTasks() {
    _cachedTasks.sort((a, b) {
      final at = a['time'];
      final bt = b['time'];
      DateTime ad = at is Timestamp ? at.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      DateTime bd = bt is Timestamp ? bt.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });
  }
}