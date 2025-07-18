import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'package:fieldframe/AuthService.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'jobber_webview_auth.dart'; // Import your AuthService

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext c) => MaterialApp(home: const AuthScreen());
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _secureStorage = const FlutterSecureStorage();
  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/drive.file'],
  );

  GoogleSignInAccount? _googleUser;
  bool _loading = false;
  String? _jobberResponse;

  @override
  void initState() {
    super.initState();
    // Attempt silent Google sign‑in
    _googleSignIn.signInSilently().then((u) {
      if (u != null) setState(() => _googleUser = u);
    });
  }

  Future<void> _pickGoogleAccount() async {
    final account = await _googleSignIn.signIn();
    if (account != null) {
      setState(() => _googleUser = account);
      final auth = await account.authentication;
      debugPrint('Google signed in: ${account.email}');
      debugPrint('ID Token: ${auth.idToken}');
      debugPrint('Access Token: ${auth.accessToken}');
    }
  }

  Future<void> _signOutGoogle() async {
    await _googleSignIn.signOut();
    setState(() {
      _googleUser = null;
      _jobberResponse = null;
    });
  }

  Future<void> _connectJobber() async {
    setState(() => _loading = true);

    // 1. Generate PKCE verifier & challenge
    final verifier = AuthService.generateCodeVerifier();
    final challenge = AuthService.generateCodeChallenge(verifier);

    await _secureStorage.write(key: 'pkce_verifier', value: verifier);

    // 2. Build the OAuth URL
    final url = AuthService.buildJobberAuthUrl(verifier);

    // 3. Navigate to web view screen
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JobberAuthPage.withVerifier(verifier),
      ),
    );


    if (result == true) {
      // Success
      setState(() {
        _loading = false;
        _jobberResponse = 'Authenticated!';
      });

      // 5. Immediately jump to your Jobs screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const JobsScreen()),
        );
      }
    } else {
      // Error
      setState(() {
        _loading = false;
        _jobberResponse = result ?? 'Authentication failed';
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final canStart = _googleUser != null && !_loading;
    return Scaffold(
      appBar: AppBar(title: const Text('Google + Jobber Auth')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: Text(
                _googleUser == null ? 'Pick Google Account' : 'Sign out Google',
              ),
              onPressed:
              _googleUser == null ? _pickGoogleAccount : _signOutGoogle,
            ),
            if (_googleUser != null) ...[
              const SizedBox(height: 8),
              Text('Signed in: ${_googleUser!.email}'),
            ],

            const SizedBox(height: 32),

            ElevatedButton.icon(
              icon: const Icon(Icons.work),
              label: Text(
                _loading
                    ? 'Authenticating…'
                    : (_jobberResponse == null
                    ? 'Connect Jobber'
                    : 'Authenticated!'),
              ),
              onPressed: canStart ? _connectJobber : null,
            ),

            if (_jobberResponse != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Raw Jobber Response:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(_jobberResponse!, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Jobs')),
    body: const Center(child: Text('🎉 Now fetch your Jobber jobs!')),
  );
}

class JobberWebViewScreen extends StatefulWidget {
  final String authUrl;
  final String codeVerifier;

  const JobberWebViewScreen({
    Key? key,
    required this.authUrl,
    required this.codeVerifier,
  }) : super(key: key);

  @override
  _JobberWebViewScreenState createState() => _JobberWebViewScreenState();
}

class _JobberWebViewScreenState extends State<JobberWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() => _isLoading = false);
            }
          },
          onNavigationRequest: (request) {
            return _handleNavigation(request.url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  NavigationDecision _handleNavigation(String url) {
    if (url.startsWith(AuthService.jobberRedirectUri)) {
      _handleRedirect(url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _handleRedirect(String url) async {
    final uri = Uri.parse(url);
    final code = uri.queryParameters['code'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      Navigator.pop(context, 'Error: $error');
    } else if (code != null) {
      try {
        await AuthService.exchangeJobberCode(code, widget.codeVerifier);
        Navigator.pop(context, true);
      } catch (e) {
        Navigator.pop(context, 'Token exchange failed: $e');
      }
    } else {
      Navigator.pop(context, 'No authorization code received');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobber Authentication'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, 'User canceled'),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}