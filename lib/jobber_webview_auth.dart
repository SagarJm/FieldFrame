import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:fieldframe/AuthService.dart';
import 'package:fieldframe/ui/ManualJobberCodeScreen.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';

import 'AuthService.dart';

class JobberAuthPage extends StatefulWidget {
  final String codeVerifier;

  const JobberAuthPage._(this.codeVerifier, {Key? key}) : super(key: key);

  // 📌 add this factory:
  factory JobberAuthPage.withVerifier(String verifier) =>
      JobberAuthPage._(verifier);

  @override
  State<JobberAuthPage> createState() => _JobberAuthPageState();
}

class _JobberAuthPageState extends State<JobberAuthPage> {
  late final String _codeVerifier;
  late final String _codeChallenge;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String _status = 'Waiting for authorization...';

  @override
  void initState() {
    super.initState();
    _codeVerifier = widget.codeVerifier;
    // Then compute the challenge from it:
    _codeChallenge = _generateCodeChallenge(_codeVerifier);
    _listenForRedirect();
    _launchJobberAuthInBrowser();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // In _JobberAuthPageState class:
  void _listenForRedirect() async {
    // Handle case when app was terminated then opened via link
    final initialUri = await _appLinks.getInitialAppLink();
    if (initialUri != null &&
        initialUri.toString().startsWith(AuthService.jobberRedirectUri)) {
      _handleUri(initialUri);
      return;
    }

    // Listen for URI while app is in foreground or background
    _sub = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('🔁 Incoming URI: $uri');
      if (uri.toString().startsWith(AuthService.jobberRedirectUri)) {
        _handleUri(uri);
      }
    });
  }

  void _handleUri(Uri uri) async {
    try {
      await AuthService.handleIncomingDeepLink(uri);
      if (mounted) {
        setState(() => _status = 'Authorized ✅');
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _status = 'Authorization failed: $e');
    }
  }




  Future<void> _launchJobberAuthInBrowser() async {
    final state = base64UrlEncode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );

    final authUrl = Uri.parse(
        '${AuthService.jobberAuthEndpoint}?'
            'response_type=code&'
            'client_id=${AuthService.jobberClientId}&'
            'redirect_uri=${AuthService.jobberRedirectUri}&'
            'code_challenge=$_codeChallenge&'
            'code_challenge_method=S256&'
            'state=$state'

    );
    debugPrint('🔗 Auth URL: $authUrl');


    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);

      // Show UI after launching browser
      await Future.delayed(const Duration(seconds: 2));

      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ManualJobberCodeScreen(codeVerifier: _codeVerifier),
        ),
      );

      if (result == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _status = '❌ Manual code entry canceled or failed.');
      }

    } else {
      throw 'Could not launch $authUrl';
    }
  }


  String _generateCodeVerifier() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = sha256.convert(utf8.encode(verifier)).bytes;
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jobber OAuth')),
      body: Center(child: Text(_status)),
    );
  }
}
