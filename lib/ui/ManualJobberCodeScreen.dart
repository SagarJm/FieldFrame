import 'package:flutter/material.dart';
import 'package:fieldframe/AuthService.dart';

class ManualJobberCodeScreen extends StatefulWidget {
  final String codeVerifier;

  const ManualJobberCodeScreen({super.key, required this.codeVerifier});

  @override
  State<ManualJobberCodeScreen> createState() => _ManualJobberCodeScreenState();
}

class _ManualJobberCodeScreenState extends State<ManualJobberCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  String _status = '';

  // In ManualJobberCodeScreen.dart
  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _status = '❗ Code is required');
      return;
    }

    setState(() => _status = '⏳ Exchanging token...');
    // try {
    //   // Use the WITH-VERIFIER version
    //   await AuthService.exchangeAuthorizationCodeWithVerifier(
    //       code,
    //       widget.codeVerifier
    //   );
    //   setState(() => _status = '✅ Authorized successfully');
    //   Navigator.pop(context, true);
    // } catch (e) {
    //   setState(() => _status = '❌ Error: $e');
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paste Jobber Auth Code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('Paste the code from webhook.site:'),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Authorization Code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: const Text('Submit Code'),
            ),
            const SizedBox(height: 12),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
