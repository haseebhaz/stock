import 'package:flutter/material.dart';
import '../config.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inventory_2, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Stock Check', style: t.headlineMedium),
            const SizedBox(height: 4),
            Text('Version $kAppVersion', style: t.titleMedium),
            const SizedBox(height: 24),
            Text('Developed by $kDeveloper', style: t.titleMedium),
          ]),
        ),
      ),
    );
  }
}
