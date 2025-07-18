// lib/ui/DriveUploadScreen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../AuthService.dart'; // adjust path as needed

class DriveUploadScreen extends StatefulWidget {
  final String jobId;

  const DriveUploadScreen({Key? key, required this.jobId}) : super(key: key);

  @override
  _DriveUploadScreenState createState() => _DriveUploadScreenState();
}

class _DriveUploadScreenState extends State<DriveUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  bool _uploading = false;
  String _status = '';

  Future<void> _captureAndUpload() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
      _uploading = true;
      _status = 'Uploading...';
    });

    try {
      // Use static method directly
      final client = await AuthService.getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);

      // 1) ensure folder exists
      final folderName = widget.jobId;
      final query =
          "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false";
      final res = await driveApi.files.list(q: query, $fields: 'files(id)');
      String folderId;
      if (res.files != null && res.files!.isNotEmpty) {
        folderId = res.files!.first.id!;
      } else {
        final folder =
            drive.File()
              ..name = folderName
              ..mimeType = 'application/vnd.google-apps.folder';
        folderId = (await driveApi.files.create(folder)).id!;
      }

      // 2) upload file
      final ts = DateTime.now().toIso8601String().replaceAll(':', '');
      final name = '${widget.jobId}_$ts${p.extension(_image!.path)}';
      final media = drive.Media(_image!.openRead(), await _image!.length());
      final fileMeta =
          drive.File()
            ..name = name
            ..parents = [folderId];
      await driveApi.files.create(fileMeta, uploadMedia: media);

      setState(() => _status = 'Upload successful');
    } catch (e) {
      setState(() => _status = 'Upload failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Upload Photo for ${widget.jobId}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _uploading ? null : _captureAndUpload,
              child: const Text('Capture & Upload'),
            ),
            const SizedBox(height: 20),
            if (_uploading) const Center(child: CircularProgressIndicator()),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_status),
              ),
          ],
        ),
      ),
    );
  }
}
