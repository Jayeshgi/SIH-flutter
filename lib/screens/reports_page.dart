import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:camera/camera.dart';
import 'package:flutter_app/models/report.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  XFile? _mediaFile;
  Position? _location;
  String? _hazardType;
  String? _imageUrl;
  final _picker = ImagePicker();
  late Box<Report> _pendingBox;
  final List<String> _hazardTypes = ['Flood', 'Tide', 'Storm', 'Cloud Burst'];
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  final String _imgbbApiKey = 'dc2d0546bd0db18f55436510ada6c3a6';

  @override
  void initState() {
    super.initState();
    _pendingBox = Hive.box<Report>('pending_reports');
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _syncPendingReports();
      }
    });
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!kIsWeb) {
      try {
        _cameras = await availableCameras();
        if (_cameras != null && _cameras!.isNotEmpty) {
          _cameraController =
              CameraController(_cameras![0], ResolutionPreset.medium);
          await _cameraController!.initialize();
          if (mounted) {
            setState(() {});
          }
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera initialization failed: $e')),
        );
      }
    }
  }

  Future<String?> _compressImage(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;
      img.Image resizedImage = img.copyResize(image, width: 800, height: 600);
      var compressed = img.encodeJpg(resizedImage, quality: 85);
      return base64Encode(compressed);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image compression failed: $e')),
      );
      return null;
    }
  }

  Future<String?> _uploadToImgbb(XFile file) async {
    try {
      final compressedBase64 = await _compressImage(file);
      if (compressedBase64 == null) return null;

      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload'),
        body: {
          'key': _imgbbApiKey,
          'image': compressedBase64,
          'expiration': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']['url'] as String?;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('ImgBB upload failed: ${response.statusCode}')),
        );
        return null;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ImgBB upload error: $e')),
      );
      return null;
    }
  }

  Future<void> _captureMediaAndLocation() async {
    bool cameraGranted = await Permission.camera.request().isGranted;
    bool locationGranted = await Permission.location.request().isGranted;

    if (!cameraGranted || !locationGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Camera and location permissions required')),
      );
      return;
    }

    if (kIsWeb) {
      try {
        _location = Position(
          latitude: 19.0760,
          longitude: 72.8777,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
        _locationController.text =
            '${_location!.latitude}, ${_location!.longitude}';
        final input = html.FileUploadInputElement()..accept = 'image/*';
        input.click();
        await input.onChange.first;
        final files = input.files;
        if (files!.isNotEmpty) {
          final file = files[0];
          final reader = html.FileReader();
          reader.readAsArrayBuffer(file);
          await reader.onLoad.first;
          _mediaFile = XFile.fromData(
            reader.result as Uint8List,
            name: file.name,
            mimeType: file.type,
          );
          setState(() {});
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e')),
        );
      }
    } else {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
        return;
      }

      try {
        _location = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _locationController.text =
            '${_location!.latitude}, ${_location!.longitude}';
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          final XFile? file = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CameraPreviewScreen(
                controller: _cameraController!,
                onCapture: (XFile file) {
                  Navigator.pop(context, file);
                },
                onRetake: () {
                  Navigator.pop(context);
                },
              ),
              settings: const RouteSettings(name: 'CameraPreview'),
            ),
          );
          if (file != null) {
            _mediaFile = file;
            setState(() {});
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera not initialized')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        return;
      }
    }
  }

  Future<void> _submitReport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushNamed(context, '/signin');
      return;
    }

    if (_formKey.currentState!.validate() &&
        _location != null &&
        _hazardType != null) {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (_mediaFile != null) {
        _imageUrl = await _uploadToImgbb(_mediaFile!);
        _mediaFile = null;
        if (_imageUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Image upload failed, report submitted without image.')),
          );
        }
      }
      if (connectivityResult != ConnectivityResult.none) {
        await _uploadOnline(user.uid, _imageUrl);
      } else {
        await _storeOffline(user.uid, _imageUrl);
      }
      _clearForm();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields!')),
      );
    }
  }

  Future<void> _uploadOnline(String userId, String? imageUrl) async {
    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'description': _descriptionController.text,
        'latitude': _location!.latitude,
        'longitude': _location!.longitude,
        'timestamp': Timestamp.now(),
        'hazardType': _hazardType,
        'userId': userId,
        'mediaUrl': imageUrl,
        'status': 'unverified',
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report uploaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _storeOffline(String userId, String? imageUrl) async {
    try {
      final report = Report(
        description: _descriptionController.text,
        latitude: _location!.latitude,
        longitude: _location!.longitude,
        hazardType: _hazardType!,
        userId: userId,
        mediaUrl: imageUrl,
      );
      await _pendingBox.add(report);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report stored offline!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offline storage failed: $e')),
      );
    }
  }

  Future<void> _syncPendingReports() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      for (var key in _pendingBox.keys) {
        final report = _pendingBox.get(key);
        if (report == null) continue;
        await FirebaseFirestore.instance.collection('reports').add({
          'description': report.description,
          'latitude': report.latitude,
          'longitude': report.longitude,
          'timestamp': Timestamp.now(),
          'hazardType': report.hazardType,
          'userId': report.userId,
          'mediaUrl': report.mediaUrl,
          'status': 'unverified',
        });
        await _pendingBox.delete(key);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    }
  }

  void _clearForm() {
    _descriptionController.clear();
    _mediaFile = null;
    _location = null;
    _locationController.clear();
    _hazardType = null;
    _imageUrl = null;
    setState(() {});
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Report'),
        backgroundColor: Colors.blue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Share Your Report',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _captureMediaAndLocation,
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: _mediaFile != null
                              ? Image.file(
                                  File(_mediaFile!.path),
                                  fit: BoxFit.cover,
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.camera_alt,
                                        size: 40, color: Colors.blue),
                                    SizedBox(height: 10),
                                    Text(
                                      'Add Image',
                                      style: TextStyle(
                                          fontSize: 18, color: Colors.blue),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    if (_mediaFile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _captureMediaAndLocation,
                              child: const Text('Retake Image'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      hint: const Text('Select Hazard Type'),
                      value: _hazardType,
                      items: _hazardTypes
                          .map((type) =>
                              DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (value) => setState(() => _hazardType = value),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Choose a hazard type',
                      ),
                      validator: (value) =>
                          value == null ? 'Please select a hazard type' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        hintText: 'Describe the hazard',
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Please enter a description' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                        hintText: 'Location will auto-populate',
                      ),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        child: const Text('Submit Report',
                            style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CameraPreviewScreen extends StatelessWidget {
  final CameraController controller;
  final Function(XFile) onCapture;
  final VoidCallback onRetake;

  const CameraPreviewScreen({
    super.key,
    required this.controller,
    required this.onCapture,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Preview'),
        backgroundColor: Colors.blue,
      ),
      body: Hero(
        tag: 'cameraPreview', // Unique Hero tag
        child: controller.value.isInitialized
            ? Stack(
                children: [
                  CameraPreview(controller),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: onRetake,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red),
                            child: const Text('Retake'),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              try {
                                final file = await controller.takePicture();
                                onCapture(file);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Capture failed: $e')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green),
                            child: const Text('Capture'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}