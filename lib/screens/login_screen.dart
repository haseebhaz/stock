import 'package:flutter/material.dart';
import '../app_state.dart';
import '../config.dart';

class LoginScreen extends StatefulWidget {
  final AppState state;
  const LoginScreen({super.key, required this.state});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _key = TextEditingController();
  List<String> _dbs = [];
  String? _db;
  bool _busy = false, _loadingDbs = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user.text = widget.state.savedLogin ?? '';
    _loadDbs();
  }

  Future<void> _loadDbs() async {
    setState(() {
      _loadingDbs = true;
      _error = null;
    });
    try {
      final dbs = await widget.state.client.listDatabases();
      setState(() {
        _dbs = dbs;
        _db = dbs.contains(widget.state.savedDb)
            ? widget.state.savedDb
            : (dbs.length == 1 ? dbs.first : null);
      });
    } catch (e) {
      setState(() => _error = 'Cannot load databases: $e');
    } finally {
      setState(() => _loadingDbs = false);
    }
  }

  Future<void> _login() async {
    if (_db == null || _user.text.trim().isEmpty || _key.text.isEmpty) {
      setState(() => _error = 'Select database and enter login and API key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.login(_db!, _user.text.trim(), _key.text);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Check – Login')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(kOdooUrl, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        if (_loadingDbs)
          const LinearProgressIndicator()
        else
          DropdownButtonFormField<String>(
            value: _db,
            decoration: const InputDecoration(labelText: 'Database', border: OutlineInputBorder()),
            items: _dbs.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => _db = v),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'Odoo login', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: 'API key', helperText: 'Odoo: My Profile > Account Security > New API Key',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Log in'),
          ),
        ),
        if (_dbs.isEmpty && !_loadingDbs)
          TextButton(onPressed: _loadDbs, child: const Text('Retry loading databases')),
      ]),
    );
  }
}
