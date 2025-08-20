import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:my_webrtc_videocall/signalling.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase with error handling
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDz_Sj2DAMvGIhZhxHvod8XX-EDGiZvOEE",
        authDomain: "flutterwebrtc-ac02f.firebaseapp.com",
        projectId: "flutterwebrtc-ac02f",
        storageBucket: "flutterwebrtc-ac02f.firebasestorage.app",
        messagingSenderId: "375277400045",
        appId: "1:375277400045:web:fe005147fbb109100781e4",
        measurementId: "G-GW33QHMXZL",
      ),
    );
    print("Firebase initialized successfully");
  } catch (e) {
    print("Firebase initialization error: $e");
    // Continue without Firebase for now
  }

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebRTC Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String? roomId;
  TextEditingController textEditingController = TextEditingController(text: '');
  bool _isInitializing = true;
  String _initializationError = '';
  bool _cameraOpened = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize renderers
      await _initializeRenderers();

      // Request permissions (don't await - let it run in background)
      if (!kIsWeb) {
        _requestPermissions();
      }

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      print("Initialization error: $e");
      setState(() {
        _isInitializing = false;
        _initializationError = e.toString();
      });
    }
  }

  Future<void> _initializeRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      // Set up the callback for remote stream
      signaling.onAddRemoteStream = ((stream) {
        print('📺 Main: onAddRemoteStream callback triggered');
        if (mounted) {
          setState(() {
            print('📺 Main: UI updated for remote stream');
          });
        }
      });
    } catch (e) {
      print("Renderer initialization error: $e");
      throw e;
    }
  }

  Future<void> _requestPermissions() async {
    try {
      // Request camera and microphone permissions
      Map<Permission, PermissionStatus> statuses =
          await [Permission.camera, Permission.microphone].request();

      // Check if permissions are granted
      if (statuses[Permission.camera] != PermissionStatus.granted ||
          statuses[Permission.microphone] != PermissionStatus.granted) {
        print('Camera or Microphone permission not granted');
      }
    } catch (e) {
      print("Permission request error: $e");
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _showImagePreview(
    BuildContext context,
    String documentId,
    String imageId,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.7,
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            imageId,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Image Display
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(16),
                      child: FutureBuilder<String?>(
                        future: signaling.getImageDataUrl(documentId),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator());
                          } else if (snapshot.hasData &&
                              snapshot.data != null) {
                            return InteractiveViewer(
                              panEnabled: true,
                              boundaryMargin: EdgeInsets.all(100),
                              minScale: 0.5,
                              maxScale: 4,
                              child: Image.network(
                                snapshot.data!,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.broken_image,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text('Failed to load image'),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          } else {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 16),
                                  Text('Image not available'),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),

                  // Action Buttons
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      border: Border(top: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: Icon(Icons.open_in_new),
                          label: Text('Open in New Tab'),
                          onPressed:
                              () => signaling.viewImageInNewTab(documentId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: Icon(Icons.download),
                          label: Text('Download'),
                          onPressed: () async {
                            await signaling.downloadRoomImage(documentId);
                            _showSnackBar("Image downloaded!");
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen during initialization
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing WebRTC...'),
            ],
          ),
        ),
      );
    }

    // Show error screen if initialization failed
    if (_initializationError.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Initialization Failed'),
              SizedBox(height: 8),
              Text(_initializationError),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isInitializing = true;
                    _initializationError = '';
                  });
                  _initializeApp();
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Flutter WebRTC Tutorial"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(
                onPressed:
                    _cameraOpened
                        ? () async {
                          try {
                            await signaling.closeUserMedia(_localRenderer);
                            setState(() {
                              _cameraOpened = !_cameraOpened;
                            });
                          } catch (e) {
                            print("Error closing camera: $e");
                            _showSnackBar(
                              "Error closing camera: ${e.toString()}",
                            );
                          }
                        }
                        : () async {
                          try {
                            // ** CHECK PERMISSIONS BEFORE OPENING CAMERA
                            if (!kIsWeb) {
                              bool hasPermissions = await _checkPermissions();
                              if (!hasPermissions) {
                                _showPermissionDialog();
                                return;
                              }
                            }
                            await signaling.openUserMedia(
                              _localRenderer,
                              _remoteRenderer,
                            );
                            setState(() {
                              _cameraOpened = !_cameraOpened;
                            });
                            print('📷 Main: Camera opened successfully');
                          } catch (e) {
                            print("Error opening camera: $e");
                            _showSnackBar(
                              "Error opening camera: ${e.toString()}",
                            );
                          }
                        },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cameraOpened ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cameraOpened ? "Close Camera & Mic" : "Open Camera & Mic",
                ),
              ),
              ElevatedButton(
                onPressed:
                    !_cameraOpened || roomId != null
                        ? null
                        : () async {
                          try {
                            String? newRoomId = await signaling.createRoom(
                              _remoteRenderer,
                            );
                            if (newRoomId != null) {
                              textEditingController.text = newRoomId;
                              print(
                                '🏠 Main: Room created with ID: $newRoomId',
                              );
                              setState(() {
                                roomId = newRoomId;
                              });
                              _showSnackBar("Room created: $newRoomId");
                            }
                          } catch (e) {
                            print("Error creating room: $e");
                            _showSnackBar(
                              "Error creating room: ${e.toString()}",
                            );
                          }
                        },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: Text("Create Room"),
              ),
              ElevatedButton(
                onPressed:
                    !_cameraOpened || roomId != null
                        ? null
                        : () async {
                          try {
                            final roomIdText =
                                textEditingController.text.trim();
                            if (roomIdText.isNotEmpty) {
                              print(
                                '🚪 Main: Attempting to join room: $roomIdText',
                              );
                              bool success = await signaling.joinRoom(
                                roomIdText,
                                _remoteRenderer,
                              );
                              if (success) {
                                print('✅ Main: Successfully joined room');
                                setState(() {
                                  roomId = roomIdText;
                                });
                                _showSnackBar("Successfully joined room");
                              } else {
                                print('❌ Main: Failed to join room');
                                _showSnackBar(
                                  "Failed to join room - room may not exist",
                                );
                              }
                            } else {
                              _showSnackBar("Please enter a room ID");
                            }
                          } catch (e) {
                            print("Error joining room: $e");
                            _showSnackBar(
                              "Error joining room: ${e.toString()}",
                            );
                          }
                        },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: Text("Join Room"),
              ),

              ElevatedButton(
                onPressed:
                    (roomId == null)
                        ? null
                        : () async {
                          try {
                            final images = await signaling.getRoomImages();

                            showDialog(
                              context: context,
                              builder:
                                  (context) => Dialog(
                                    child: Container(
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.8,
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.8,
                                      padding: EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          // Header
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Room $roomId Images (${images.length})',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.close),
                                                onPressed:
                                                    () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(),
                                              ),
                                            ],
                                          ),
                                          Divider(),

                                          // Images List
                                          Expanded(
                                            child:
                                                images.isEmpty
                                                    ? Center(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .image_not_supported,
                                                            size: 64,
                                                            color: Colors.grey,
                                                          ),
                                                          SizedBox(height: 16),
                                                          Text(
                                                            'No images captured in this room yet',
                                                          ),
                                                          SizedBox(height: 8),
                                                          Text(
                                                            'Take some pictures during your video call!',
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                    : ListView.builder(
                                                      itemCount: images.length,
                                                      itemBuilder: (
                                                        context,
                                                        index,
                                                      ) {
                                                        final image =
                                                            images[index];
                                                        final documentId =
                                                            image['document_id']
                                                                as String;
                                                        final imageId =
                                                            image['image_id']
                                                                as String;
                                                        final timestamp =
                                                            image['local_timestamp']
                                                                as int;
                                                        final fileSize =
                                                            image['file_size']
                                                                as int;
                                                        final capturedBy =
                                                            image['captured_by']
                                                                as String? ??
                                                            'unknown';
                                                        final date =
                                                            DateTime.fromMillisecondsSinceEpoch(
                                                              timestamp,
                                                            );

                                                        return Card(
                                                          margin:
                                                              EdgeInsets.symmetric(
                                                                vertical: 4,
                                                              ),
                                                          child: ListTile(
                                                            leading: CircleAvatar(
                                                              backgroundColor:
                                                                  Colors.blue,
                                                              child: Icon(
                                                                Icons.image,
                                                                color:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                            ),
                                                            title: Text(
                                                              imageId,
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                            subtitle: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  '📅 ${date.toString().substring(0, 19)}',
                                                                ),
                                                                Text(
                                                                  '💾 ${(fileSize / 1024).toStringAsFixed(1)} KB',
                                                                ),
                                                                Text(
                                                                  '👤 Captured by: $capturedBy',
                                                                ),
                                                                Text(
                                                                  '🏠 Room: $roomId',
                                                                ),
                                                              ],
                                                            ),
                                                            trailing: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                IconButton(
                                                                  icon: Icon(
                                                                    Icons
                                                                        .visibility,
                                                                    color:
                                                                        Colors
                                                                            .green,
                                                                  ),
                                                                  onPressed: () async {
                                                                    await signaling
                                                                        .viewImageInNewTab(
                                                                          documentId,
                                                                        );
                                                                  },
                                                                  tooltip:
                                                                      'View in New Tab',
                                                                ),
                                                                IconButton(
                                                                  icon: Icon(
                                                                    Icons
                                                                        .download,
                                                                    color:
                                                                        Colors
                                                                            .blue,
                                                                  ),
                                                                  onPressed: () async {
                                                                    await signaling
                                                                        .downloadRoomImage(
                                                                          documentId,
                                                                        );
                                                                    _showSnackBar(
                                                                      "Image downloaded!",
                                                                    );
                                                                  },
                                                                  tooltip:
                                                                      'Download',
                                                                ),
                                                                IconButton(
                                                                  icon: Icon(
                                                                    Icons
                                                                        .fullscreen,
                                                                    color:
                                                                        Colors
                                                                            .purple,
                                                                  ),
                                                                  onPressed: () {
                                                                    _showImagePreview(
                                                                      context,
                                                                      documentId,
                                                                      imageId,
                                                                    );
                                                                  },
                                                                  tooltip:
                                                                      'Preview',
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                          ),

                                          // Footer Actions
                                          if (images.isNotEmpty)
                                            Padding(
                                              padding: EdgeInsets.only(top: 16),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  ElevatedButton.icon(
                                                    icon: Icon(Icons.download),
                                                    label: Text('Download All'),
                                                    onPressed: () async {
                                                      for (final image
                                                          in images) {
                                                        await signaling
                                                            .downloadRoomImage(
                                                              image['document_id'],
                                                            );
                                                      }
                                                      _showSnackBar(
                                                        "All images downloaded!",
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                            );
                          } catch (e) {
                            _showSnackBar(
                              "Error loading room images: ${e.toString()}",
                            );
                          }
                        },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (roomId == null) ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text("View Room Images"),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await signaling.hangUp(_localRenderer);
                    setState(() {
                      roomId = null;
                      _cameraOpened = false;
                      textEditingController.clear();
                    });
                    print('📞 Main: Hung up and cleared room ID');
                    _showSnackBar("Call ended");
                  } catch (e) {
                    print("Error hanging up: $e");
                    _showSnackBar("Error hanging up: ${e.toString()}");
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text("Hang Up"),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await signaling.takeCustomerPicture();
                    print('📷 Customer Picture Taken');
                    _showSnackBar("Request Sent");
                  } catch (e) {
                    print("Error requesting: $e");
                    _showSnackBar("Error requesting: ${e.toString()}");
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: Text("Take Customer Picture"),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child:
                  kIsWeb || MediaQuery.of(context).size.width > 600
                      ? Stack(
                        children: [
                          Positioned.fill(
                            child: _buildVideoContainer(
                              _remoteRenderer,
                              "Your Friend",
                              false,
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            right: 50,
                            child: SizedBox(
                              height: 200,
                              width: 300,
                              child: _buildVideoContainer(
                                _localRenderer,
                                "You",
                                true,
                              ),
                            ),
                          ),
                        ],
                      )
                      : Stack(
                        children: [
                          Positioned.fill(
                            child: _buildVideoContainer(
                              _remoteRenderer,
                              "Your Friend",
                              false,
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            right: 20,
                            child: SizedBox(
                              height: 150,
                              width: 100,
                              child: _buildVideoContainer(
                                _localRenderer,
                                "You",
                                true,
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Text(
                  "Room ID: ",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: TextField(
                    controller: textEditingController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Enter room ID to join",
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      suffixIcon:
                          roomId != null
                              ? IconButton(
                                icon: Icon(Icons.copy),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: textEditingController.text,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "Room ID copied to clipboard",
                                      ),
                                    ),
                                  );
                                },
                              )
                              : null,
                    ),
                    readOnly: roomId != null,
                  ),
                ),
              ],
            ),
          ),
          // Status information
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                if (roomId != null)
                  Text(
                    'Connected to room: $roomId',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text('Camera: ${_cameraOpened ? "✅" : "❌"}'),
                    Text(
                      'Local stream: ${_localRenderer.srcObject != null ? "✅" : "❌"}',
                    ),
                    Text(
                      'Remote stream: ${_remoteRenderer.srcObject != null ? "✅" : "❌"}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildVideoContainer(
    RTCVideoRenderer renderer,
    String label,
    bool isMirror,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
        color: Colors.black12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            // Show video if stream is available, otherwise show placeholder
            renderer.srcObject != null
                ? RTCVideoView(renderer, mirror: isMirror)
                : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        label == "Local"
                            ? Icons.videocam_off
                            : Icons.person_off,
                        size: 48,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 8),
                      Text(
                        label == "Local"
                            ? "Camera off"
                            : "Waiting for remote...",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$label ${renderer.srcObject != null ? "🟢" : "🔴"}',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _checkPermissions() async {
    try {
      final cameraStatus = await Permission.camera.status;
      final microphoneStatus = await Permission.microphone.status;

      return cameraStatus.isGranted && microphoneStatus.isGranted;
    } catch (e) {
      print("Permission check error: $e");
      return false;
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Permissions Required'),
            content: Text(
              'Camera and microphone permissions are required for video calling.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: Text('Open Settings'),
              ),
            ],
          ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: 3)),
      );
    }
  }
}
