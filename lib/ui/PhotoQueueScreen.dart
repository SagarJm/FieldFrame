// lib/ui/PhotoQueueScreen.dart

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../AuthService.dart';
import '../model/Job.dart';

class PhotoQueueScreen extends StatefulWidget {
  const PhotoQueueScreen({Key? key}) : super(key: key);

  @override
  State<PhotoQueueScreen> createState() => _PhotoQueueScreenState();
}

class _PhotoQueueScreenState extends State<PhotoQueueScreen> {
  Job? job;
  String _status = '';
  int _retryCount = 0;
  final int _maxRetries = 2;
  bool _isUploading = false;


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    job =
        route?.settings.arguments is Job
            ? route!.settings.arguments as Job
            : Job(id: 'demo', name: 'Demo Job');
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permissions =
          sdk >= 33
              ? [Permission.camera, Permission.photos]
              : [Permission.camera, Permission.storage];

      final statuses = await permissions.request();
      return statuses.values.every((s) => s.isGranted);
    } else {
      final statuses = await [Permission.camera, Permission.photos].request();
      return statuses.values.every((s) => s.isGranted);
    }
  }

  Future<File?> _pickImage(ImageSource src) async {
    if (!await _requestPermissions()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permissions not granted')));
      return null;
    }

    final xfile = await ImagePicker().pickImage(source: src, imageQuality: 85);
    return xfile == null ? null : File(xfile.path);
  }

  Future<void> _handleImage(ImageSource src) async {
    setState(() {
      _status = 'Picking image…';
      _retryCount = 0;
    });

    try {
      final file = await _pickImage(src);
      if (file == null || !file.existsSync()) {
        setState(() => _status = 'No image selected or file not found.');
        return;
      }

      debugPrint('Selected file: ${file.path}');
      debugPrint('Job ID: ${job?.id}');

      await _attemptUploadWithReauth(file);
    } catch (e) {
      setState(() => _status = 'Error: ${e.toString()}');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: ${e.toString()}')));
    }
  }

  Future<void> _attemptUploadWithReauth(File file) async {
    try {
      await _performUpload(file);
    } catch (e) {
      if (_retryCount < _maxRetries &&
          (e.toString().contains('authentication') ||
              e.toString().contains('reauthenticate'))) {
        _retryCount++;
        debugPrint(
          'Auth error detected - attempting reauthentication (attempt $_retryCount)',
        );

        setState(() => _status = 'Reauthenticating...');

        // Sign out completely before reauthentication
        await AuthService.signOutGoogle();

        final user = await AuthService.signInWithGoogle();
        if (user == null) {
          throw Exception('Reauthentication canceled by user');
        }

        // Add delay to ensure auth state is updated
        await Future.delayed(const Duration(seconds: 1));

        await _attemptUploadWithReauth(file);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _performUpload(File file) async {
    setState(() {
      _isUploading = true;
      _status = 'Uploading to Google Drive…';
    });

    final gToken = await AuthService.getGoogleAccessToken();

    if (gToken.isEmpty) {
      setState(() => _isUploading = false);
      throw Exception('Google Access Token is missing');
    }

    final folderId = await _ensureDriveFolder(job!.id);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filename = '${job?.id}_$ts.jpg';

    await _uploadToDrive(file, filename, folderId, gToken);

    try {
      setState(() => _status = 'Uploading to Jobber…');
      final jToken = await AuthService.getJobberAccessToken();
      await _uploadToJobber(file, filename, job!.id, jToken);
    } catch (e) {
      debugPrint('⚠️ Skipping Jobber upload: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploaded to Drive. Jobber not linked.')),
      );
    }

    setState(() {
      _status = '✅ Uploaded $filename';
      _isUploading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Uploaded $filename')),
    );
  }


  Future<String> _ensureDriveFolder(String jobId) async {
    final accessToken = await AuthService.getGoogleAccessToken();
    final query = Uri.encodeComponent(
      "mimeType='application/vnd.google-apps.folder' and name='$jobId' and trashed=false",
    );
    final listUri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=$query',
    );

    final listRes = await http.get(
      listUri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (listRes.statusCode == 200) {
      final listJson = jsonDecode(listRes.body) as Map<String, dynamic>;
      final files = listJson['files'] as List<dynamic>;
      if (files.isNotEmpty) return files.first['id'];
    }

    // Create new folder
    final createRes = await http.post(
      Uri.parse('https://www.googleapis.com/drive/v3/files'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': jobId,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );

    if (createRes.statusCode == 200) {
      final createJson = jsonDecode(createRes.body);
      return createJson['id'];
    }

    throw Exception('Drive folder creation failed: ${createRes.statusCode}');
  }

  Future<void> _uploadToDrive(
    File file,
    String name,
    String folderId,
    String token,
  ) async {
    final uri = Uri.parse(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
    );

    // Create multipart request
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token';

    // Add metadata as JSON part
    request.files.add(
      http.MultipartFile.fromString(
        'metadata',
        jsonEncode({
          'name': name,
          'parents': [folderId],
        }),
        contentType: MediaType('application', 'json'),
      ),
    );

    // Add file part
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    // Send and handle response
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      debugPrint('Drive upload failed: ${response.statusCode}');
      debugPrint('Response body: $responseBody');
      throw Exception(
        'Drive upload failed: ${response.statusCode} - $responseBody',
      );
    }
  }

  Future<void> _uploadToJobber(
    File file,
    String name,
    String jobId,
    String token,
  ) async {
    final req =
        http.MultipartRequest(
            'POST',
            Uri.parse('https://api.getjobber.com/v1/notes'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['jobId'] = jobId
          ..fields['note'] = name
          ..files.add(
            await http.MultipartFile.fromPath('attachment', file.path),
          );

    final resp = await req.send();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Jobber upload failed: ${resp.statusCode}');
    }
  }

  Widget _buildSquareButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 120,
      height: 120,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Upload Photos for ${job?.name}')),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/bg.jpg'),
            // Ensure this image exists
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.3),
              BlendMode.dstATop,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSquareButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    color: Colors.blueAccent,
                    onPressed: () => _handleImage(ImageSource.camera),
                  ),
                  const SizedBox(width: 24),
                  _buildSquareButton(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    color: Colors.green,
                    onPressed: () => _handleImage(ImageSource.gallery),
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _isUploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  _status,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}
