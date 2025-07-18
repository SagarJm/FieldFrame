import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class AuthService {
  // Google OAuth Configuration
  static const storage = FlutterSecureStorage();

  static const _googleClientId =
      '108056215116-itucof3697c1ae58909ccem685orh9fm.apps.googleusercontent.com';
  static const _googleScopes = [
    'email',
    'https://www.googleapis.com/auth/drive.file',
  ];

  // Jobber OAuth Configuration
  static const jobberClientId = '6a9d210f-c96d-4c61-8b58-c3dd681a9234';
  static const jobberClientSecret =
      '5d840e5aa72602d981ec5b4dc3ff6c394b743d682faeac6f2d6b039f51e9bb42';
  static const jobberAuthEndpoint =
      'https://secure.getjobber.com/oauth/authorize';
  static const jobberTokenEndpoint = 'https://api.getjobber.com/oauth/token';
  static const jobberRedirectUri = 'https://webhook.site/8bd46422-7e67-477e-9c12-557099e3357c';

  // Secure storage & GoogleSignIn instance
  static final _storage = FlutterSecureStorage();
  static final _googleSignIn = GoogleSignIn(scopes: _googleScopes);

  // Track authentication state
  static bool get isGoogleSignedIn => _googleSignIn.currentUser != null;

  // ---------------- Google Sign‑In ----------------

  /// Launches interactive Google sign-in.
  static Future<GoogleSignInAccount?> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();

      if (account == null) {
        debugPrint('❌ Google sign-in canceled by user');
        return null;
      }

      // Get the authentication info
      final auth = await account.authentication;

      debugPrint('✅ Google Sign-In Successful');
      debugPrint('👤 Name: ${account.displayName}');
      debugPrint('📧 Email: ${account.email}');
      debugPrint('🆔 ID: ${account.id}');
      debugPrint('🔐 ID Token: ${auth.idToken}');
      debugPrint('🔑 Access Token: ${auth.accessToken}');

      return account;
    } catch (e) {
      debugPrint('❌ Google sign-in error: $e');
      return null;
    }
  }

  static Future<String> getGoogleAccessToken() async {
    try {
      // Check current user
      var user = _googleSignIn.currentUser;

      // If no user, try silent sign-in
      if (user == null) {
        user = await _googleSignIn.signInSilently();
      }

      // If still no user, trigger interactive sign-in
      if (user == null) {
        debugPrint('No Google user found - triggering interactive sign-in');
        user = await _googleSignIn.signIn();
        if (user == null) throw Exception('Google sign-in canceled by user');
      }

      // Get authentication object
      final auth = await user.authentication;
      final token = auth.accessToken;

      if (token == null || token.isEmpty) {
        throw Exception(
          'Google access token is missing. Please reauthenticate.',
        );
      }

      return token;
    } catch (e) {
      debugPrint('Google Access Token Error: $e');
      rethrow;
    }
  }

  // ---------------- Jobber PKCE OAuth ----------------

  /// Generates a secure random PKCE verifier.
  static String generateCodeVerifier() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Computes the SHA256-based code challenge.
  static String generateCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  /// Exchanges authorization code for Jobber tokens.
  static Future<void> exchangeJobberCode(
    String code,
    String codeVerifier,
  ) async {
    final resp = await http.post(
      Uri.parse(jobberTokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': jobberClientId,
        'client_secret': jobberClientSecret,
        'redirect_uri': jobberRedirectUri,
        'code': code,
        'code_verifier': codeVerifier,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('Jobber auth failed: ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    if (data['access_token'] == null) {
      throw Exception(
        'Jobber auth failed: ${data['error_description'] ?? resp.body}',
      );
    }

    await _storage.write(
      key: 'jobber_access_token',
      value: data['access_token'],
    );
    await _storage.write(
      key: 'jobber_refresh_token',
      value: data['refresh_token'],
    );

    // 👇 Print all data for debugging
    debugPrint('🔐 Jobber Auth Response:');
    debugPrint('Access Token: ${data['access_token']}');
    debugPrint('Refresh Token: ${data['refresh_token']}');
    debugPrint('Expires In: ${data['expires_in']}');
    debugPrint('Token Type: ${data['token_type']}');
    debugPrint('Scope: ${data['scope']}');

    final expiry = DateTime.now().add(Duration(seconds: data['expires_in']));
    await _storage.write(key: 'jobber_expiry', value: expiry.toIso8601String());
  }

  /// Returns a valid Jobber access token, auto‑refreshing if expired.
  static Future<String> getJobberAccessToken() async {
    final token = await _storage.read(key: 'jobber_access_token');
    final expiryStr = await _storage.read(key: 'jobber_expiry');

    if (token == null || expiryStr == null) {
      throw Exception('Jobber not authenticated');
    }

    final expiry = DateTime.parse(expiryStr);
    if (DateTime.now().isAfter(expiry)) {
      final refresh = await _storage.read(key: 'jobber_refresh_token');
      if (refresh == null) throw Exception('No Jobber refresh token');

      final resp = await http.post(
        Uri.parse(jobberTokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'client_id': jobberClientId,
          'client_secret': jobberClientSecret,
          'refresh_token': refresh,
        },
      );

      if (resp.statusCode != 200) {
        throw Exception(
          'Jobber refresh failed: ${resp.statusCode} - ${resp.body}',
        );
      }

      final data = jsonDecode(resp.body);
      if (data['access_token'] == null) {
        throw Exception(
          'Jobber refresh failed: ${data['error_description'] ?? resp.body}',
        );
      }

      await _storage.write(
        key: 'jobber_access_token',
        value: data['access_token'],
      );
      final newExp = DateTime.now().add(Duration(seconds: data['expires_in']));
      await _storage.write(
        key: 'jobber_expiry',
        value: newExp.toIso8601String(),
      );
      return data['access_token'];
    }
    return token;
  }

  // ========== UTILITY METHODS ==========
  static String buildJobberAuthUrl(String codeVerifier) {
    final codeChallenge = generateCodeChallenge(codeVerifier);

    return '$jobberAuthEndpoint?'
        'response_type=code&'
        'client_id=${Uri.encodeComponent(jobberClientId)}&'
        'redirect_uri=${Uri.encodeComponent(jobberRedirectUri)}&'
        'scope=${Uri.encodeComponent('clients:read jobs:read')}&'
        'code_challenge=${Uri.encodeComponent(codeChallenge)}&'
        'code_challenge_method=S256';
  }

  static Future<void> storePKCEVerifier(String verifier) async {
    await _storage.write(key: 'pkce_verifier', value: verifier);
  }

  static Future<String?> getStoredPKCEVerifier() async {
    return await _storage.read(key: 'pkce_verifier');
  }

  static Future<void> handleIncomingDeepLink(Uri uri) async {
    debugPrint('🔗 Handling deep link: $uri');

    // Handle success case
    if (uri.queryParameters.containsKey('code')) {
      final code = uri.queryParameters['code'];
      final verifier = await getStoredPKCEVerifier();
      debugPrint('✅ Received code: $code');

      if (code != null && verifier != null) {
        await exchangeJobberCode(code, verifier);


        debugPrint('✅ Token exchange completed successfully');
        return;
      }
    }

    // Handle error case
    if (uri.queryParameters.containsKey('error')) {
      final error = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];
      throw Exception('Authorization failed: $error - $errorDescription');
    }

    throw Exception('Unhandled deep link: $uri');
  }



  static Future<bool> launchAuthInBrowser(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Browser launch failed: $e');
      return false;
    }
  }

  /// Sign out from Google
  static Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
    await _googleSignIn.disconnect();
  }

  /// Returns an authenticated client with Google token headers
  static Future<http.Client> getAuthenticatedClient() async {
    final token = await getGoogleAccessToken();
    return _AuthenticatedHttpClient(token);
  }
}

// Injects Bearer token in every request
class _AuthenticatedHttpClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  _AuthenticatedHttpClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}
