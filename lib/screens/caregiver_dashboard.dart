import 'package:flutter/material.dart';

class CaregiverDashboard extends StatelessWidget {
  const CaregiverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.assignment, size: 32),
              title: const Text('Stage / Severity Assessment'),
              subtitle: const Text('Update impairment stage to tune AI questions.'),
              trailing: ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed('/assessment'),
                child: const Text('Assess'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.collections_bookmark_rounded, size: 32),
              title: const Text('Reminiscence Library'),
              subtitle: const Text('Upload media, review Memory Health Map, and guide therapy.'),
              trailing: ElevatedButton(
                onPressed: () => Navigator.of(context).pushNamed('/reminiscence'),
                child: const Text('Open'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}