import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'dart:html' as html;

class Signaling {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // final FirebaseStorage _storage = FirebaseStorage.instance;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  RTCVideoRenderer? _remoteRenderer;

  String? _currentRoomId;

  Function(MediaStream stream)? onAddRemoteStream;

  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  MediaRecorder? _mediaRecorder;

  // ** Open user media (camera + mic) and bind to localRenderer
  Future<void> openUserMedia(
    RTCVideoRenderer localRenderer,
    RTCVideoRenderer remoteRenderer,
  ) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': true,
    });
    localStream = stream;
    localRenderer.srcObject = localStream;
    _remoteRenderer = remoteRenderer; // Store remote renderer reference
    print(
      "📷 Local stream initialized with ${localStream?.getTracks().length} tracks",
    );
  }

  Future<void> closeUserMedia(RTCVideoRenderer localRenderer) async {
    localStream?.getTracks().forEach((track) {
      track.stop();
    });
    localRenderer.srcObject = null;
    print(
      "📷 Local stream ended with ${localStream?.getTracks().length} tracks",
    );
  }

  /// Create a new room (caller)
  Future<String?> createRoom(
    RTCVideoRenderer remoteRenderer, {
    bool requestImage = false,
  }) async {
    _remoteRenderer = remoteRenderer;
    DocumentReference roomRef = _firestore.collection('rooms').doc();

    // Create PeerConnection with proper configuration
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'iceCandidatePoolSize': 10,
    });

    // Add local tracks
    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    // Handle remote tracks
    peerConnection?.onTrack = (RTCTrackEvent event) async {
      print('🎥 Got remote track: ${event.track.kind}');

      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        _remoteRenderer?.srcObject = remoteStream;
        onAddRemoteStream?.call(remoteStream!);
        print('✅ Remote stream assigned to renderer');
      }
    };

    // Handle connection state changes
    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('🔗 Connection state: $state');
    };

    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('🧊 ICE connection state: $state');
    };

    // ICE candidates
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      print('🧊 Got local ICE candidate');
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    await roomRef.collection('images').add({
      'createdAt': FieldValue.serverTimestamp(),
      'fileUrl': null,
    });

    // Create offer
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    await roomRef.set({'offer': offer.toMap()});

    // Listen for remote answer
    roomRef.snapshots().listen((snapshot) async {
      final data = snapshot.data() as Map<String, dynamic>?;

      if (snapshot.exists && data != null && data.containsKey('answer')) {
        var answer = data['answer'];
        var rtcAnswer = RTCSessionDescription(answer['sdp'], answer['type']);

        if (!_isRemoteDescriptionSet) {
          await peerConnection?.setRemoteDescription(rtcAnswer);
          _isRemoteDescriptionSet = true;
          print("✅ Remote description set (answer)");
          await _addQueuedCandidates();
        }
      }
    });

    // Listen for remote ICE candidates
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var docChange in snapshot.docChanges) {
        if (docChange.type == DocumentChangeType.added) {
          var data = docChange.doc.data();
          if (data != null) {
            _safelyAddCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
        }
      }
    });
    _currentRoomId = roomRef.id;
    return roomRef.id;
  }

  /// Join an existing room (callee)
  Future<bool> joinRoom(String roomId, RTCVideoRenderer remoteRenderer) async {
    try {
      _remoteRenderer = remoteRenderer;
      DocumentReference roomRef = _firestore.collection('rooms').doc(roomId);
      DocumentSnapshot roomSnapshot = await roomRef.get();

      if (!roomSnapshot.exists) {
        print('❌ Room not found: $roomId');
        return false;
      }

      // Create PeerConnection with proper configuration
      peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'iceCandidatePoolSize': 10,
      });

      // Add local tracks
      localStream?.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });

      // Handle remote tracks
      peerConnection?.onTrack = (RTCTrackEvent event) async {
        print('🎥 Got remote track: ${event.track.kind}');

        if (event.streams.isNotEmpty) {
          remoteStream = event.streams[0];
          _remoteRenderer?.srcObject = remoteStream;
          onAddRemoteStream?.call(remoteStream!);
          print('✅ Remote stream assigned to renderer');
        }
      };

      // Handle connection state changes
      peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
        print('🔗 Connection state: $state');
      };

      peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        print('🧊 ICE connection state: $state');
      };

      // ICE candidates
      peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        print('🧊 Got local ICE candidate');
        roomRef.collection('calleeCandidates').add(candidate.toMap());
      };

      // Set remote offer
      var offerData = roomSnapshot.data() as Map<String, dynamic>?;
      if (offerData == null || !offerData.containsKey('offer')) {
        print('❌ No offer found in room');
        return false;
      }

      var offer = offerData['offer'];
      await peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      _isRemoteDescriptionSet = true;
      print("✅ Remote description set (offer)");
      await _addQueuedCandidates();

      // Create answer
      RTCSessionDescription answer = await peerConnection!.createAnswer();
      await peerConnection!.setLocalDescription(answer);

      await roomRef.update({'answer': answer.toMap()});

      // Listen for remote ICE candidates
      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var docChange in snapshot.docChanges) {
          if (docChange.type == DocumentChangeType.added) {
            var data = docChange.doc.data();
            if (data != null) {
              _safelyAddCandidate(
                RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                ),
              );
            }
          }
        }
      });

      return true;
    } catch (e) {
      print('❌ Error joining room: $e');
      return false;
    }
  }

  /// Safely add ICE candidate (queue if remoteDescription not set yet)
  Future<void> _safelyAddCandidate(RTCIceCandidate candidate) async {
    if (peerConnection != null &&
        _isRemoteDescriptionSet &&
        peerConnection!.signalingState !=
            RTCSignalingState.RTCSignalingStateClosed) {
      try {
        await peerConnection!.addCandidate(candidate);
        print('✅ Added ICE candidate immediately');
      } catch (e) {
        print('❌ Error adding ICE candidate: $e');
      }
    } else {
      _pendingCandidates.add(candidate);
      print('📝 Queued ICE candidate (${_pendingCandidates.length})');
    }
  }

  /// Add queued ICE candidates once remote description is set
  Future<void> _addQueuedCandidates() async {
    if (peerConnection == null) return;

    for (var candidate in _pendingCandidates) {
      try {
        await peerConnection!.addCandidate(candidate);
        print('✅ Added queued ICE candidate');
      } catch (e) {
        print('❌ Error adding queued ICE candidate: $e');
      }
    }
    _pendingCandidates.clear();
  }

  /// Hang up and cleanup
  Future<void> hangUp(RTCVideoRenderer localRenderer) async {
    try {
      // Stop all tracks
      localStream?.getTracks().forEach((track) {
        track.stop();
      });
      remoteStream?.getTracks().forEach((track) {
        track.stop();
      });

      // Dispose streams
      await localStream?.dispose();
      await remoteStream?.dispose();

      // Clear renderers
      localRenderer.srcObject = null;
      _remoteRenderer?.srcObject = null;

      // Close peer connection
      await peerConnection?.close();

      // Reset state
      peerConnection = null;
      localStream = null;
      remoteStream = null;
      _isRemoteDescriptionSet = false;
      _pendingCandidates.clear();

      print("📴 Call ended and cleaned up");
    } catch (e) {
      print("❌ Error during hangup: $e");
    }
  }

  Future<String?> takeCustomerPicture() async {
    try {
      if (_remoteRenderer == null || _remoteRenderer!.srcObject == null) {
        print('❌ No remote video stream available');
        throw Exception('No remote video stream available for capture');
      }

      if (_currentRoomId == null) {
        print('❌ No room ID available');
        throw Exception(
          'No room ID available - must be in a call to capture images',
        );
      }

      final videoTrack = _remoteRenderer!.srcObject!.getVideoTracks().first;
      final frameBuffer = await videoTrack.captureFrame();
      final imgBytes = frameBuffer.asUint8List();

      // Convert to base64 for Firestore storage
      final base64String = base64Encode(imgBytes);

      // Generate unique image ID with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageId = 'customer_${timestamp}';

      print('📸 Captured ${imgBytes.length} bytes for room $_currentRoomId');

      // Store in room's images subcollection
      final roomRef = _firestore.collection('rooms').doc(_currentRoomId);
      final imageDocRef = await roomRef.collection('images').add({
        'image_id': imageId,
        'image_data': base64String,
        'content_type': 'image/png',
        'file_size': imgBytes.length,
        'captured_at': FieldValue.serverTimestamp(),
        'local_timestamp': timestamp,
        'capture_type': 'remote_user_snapshot',
        'room_id': _currentRoomId,
        'captured_by': 'local_user', // You can customize this
      });

      print('✅ Customer picture saved to room $_currentRoomId');
      print('📍 Image Document ID: ${imageDocRef.id}');

      return imageDocRef.id; // Return image document ID
    } catch (e) {
      print('❌ Error capturing and storing picture: $e');
      rethrow;
    }
  }

  Future<String?> getImageDataUrl(String imageDocumentId) async {
    try {
      if (_currentRoomId == null) {
        print('❌ No room ID available');
        return null;
      }

      final roomRef = _firestore.collection('rooms').doc(_currentRoomId);
      final doc = await roomRef.collection('images').doc(imageDocumentId).get();

      if (!doc.exists) {
        print('❌ Image document not found: $imageDocumentId');
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      final base64String = data['image_data'] as String;
      final contentType = data['content_type'] as String? ?? 'image/png';

      return 'data:$contentType;base64,$base64String';
    } catch (e) {
      print('❌ Error retrieving image: $e');
      return null;
    }
  }

  /// Get image for any room (static method)
  Future<String?> getImageDataUrlForRoom(
    String roomId,
    String imageDocumentId,
  ) async {
    try {
      final roomRef = _firestore.collection('rooms').doc(roomId);
      final doc = await roomRef.collection('images').doc(imageDocumentId).get();

      if (!doc.exists) {
        print('❌ Image document not found: $imageDocumentId in room $roomId');
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;
      final base64String = data['image_data'] as String;
      final contentType = data['content_type'] as String? ?? 'image/png';

      return 'data:$contentType;base64,$base64String';
    } catch (e) {
      print('❌ Error retrieving image: $e');
      return null;
    }
  }

  /// View image in new browser tab
  Future<void> viewImageInNewTab(String imageDocumentId) async {
    try {
      final dataUrl = await getImageDataUrl(imageDocumentId);
      if (dataUrl != null) {
        html.window.open(dataUrl, '_blank');
        print('✅ Image opened in new tab');
      } else {
        print('❌ Could not get image data for viewing');
      }
    } catch (e) {
      print('❌ Error opening image: $e');
    }
  }

  /// Download image to user's computer
  Future<void> downloadRoomImage(String imageDocumentId) async {
    try {
      final dataUrl = await getImageDataUrl(imageDocumentId);
      if (dataUrl == null) {
        print('❌ Could not get image data');
        return;
      }

      if (_currentRoomId == null) return;

      final roomRef = _firestore.collection('rooms').doc(_currentRoomId);
      final doc = await roomRef.collection('images').doc(imageDocumentId).get();
      final data = doc.data() as Map<String, dynamic>;
      final imageId = data['image_id'] as String;
      final timestamp = data['local_timestamp'] as int;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

      // Create descriptive filename
      final fileName =
          '${imageId}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}_room-${_currentRoomId}.png';

      // Create download link
      final anchor =
          html.AnchorElement(href: dataUrl)
            ..setAttribute('download', fileName)
            ..style.display = 'none';

      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);

      print('✅ Image downloaded: $fileName');
    } catch (e) {
      print('❌ Error downloading image: $e');
    }
  }

  /// Get all images for the current room
  Future<List<Map<String, dynamic>>> getRoomImages() async {
    try {
      if (_currentRoomId == null) {
        print('❌ No room ID available');
        return [];
      }

      final roomRef = _firestore.collection('rooms').doc(_currentRoomId);
      final querySnapshot =
          await roomRef
              .collection('images')
              .where('image_data', isNotEqualTo: null) // Only get actual images
              .orderBy('captured_at', descending: true)
              .get();

      return querySnapshot.docs
          .map(
            (doc) => {
              'document_id': doc.id,
              'room_id': _currentRoomId,
              ...doc.data(),
              // Don't include image_data in list to save bandwidth
            }..remove('image_data'),
          )
          .toList();
    } catch (e) {
      print('❌ Error fetching room images: $e');
      return [];
    }
  }

  Future<void> startRecordStream(RTCVideoRenderer remoteRenderer) async {
    MediaStream? remoteStream = remoteRenderer.srcObject;
    if (remoteStream == null) {
      print('❌ No remote stream to record');
      return;
    }
    _mediaRecorder = MediaRecorder();
    _mediaRecorder!.startWeb(remoteStream, mimeType: 'video/webm');
    print('⏺️ Recording started');
  }

  Future<String?> stopRecordStreamAndSaveToFirebase() async {
    if (_mediaRecorder == null) {
      print('❌ No recording in progress');
      return null;
    }
    try {
      final blobUrl = await _mediaRecorder!.stop();
      print('⏹️ Recording stopped, blob URL: $blobUrl');

      // Fetch the actual blob from the URL
      final response = await html.window.fetch(blobUrl);
      final blob = await response.blob();

      print('📹 Blob size: ${blob.size} bytes');

      // Read blob as bytes for Firebase Storage
      final reader = html.FileReader();
      final completer = Completer<Uint8List>();
      reader.readAsArrayBuffer(blob);
      reader.onLoadEnd.listen((event) {
        completer.complete(reader.result as Uint8List);
      });
      final bytes = await completer.future;

      if (_currentRoomId == null) {
        print('❌ No room ID available');
        return null;
      }

      // Generate unique video ID with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoId = 'video_${timestamp}';
      final fileName = '$videoId.webm';

      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('rooms')
          .child(_currentRoomId!)
          .child('videos')
          .child(fileName);

      print('📤 Uploading video to Firebase Storage...');
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(
          contentType: 'video/webm',
          customMetadata: {
            'room_id': _currentRoomId!,
            'recorded_by': 'local_user',
            'local_timestamp': timestamp.toString(),
          },
        ),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      print('✅ Video uploaded to Firebase Storage');
      print('🔗 Download URL: $downloadUrl');

      // Save metadata to Firestore (optional - just metadata, not the video data)
      final roomRef = _firestore.collection('rooms').doc(_currentRoomId);
      final videoDocRef = await roomRef.collection('videos').add({
        'video_id': videoId,
        'file_name': fileName,
        'download_url': downloadUrl,
        'storage_path': 'rooms/$_currentRoomId/videos/$fileName',
        'content_type': 'video/webm',
        'file_size': bytes.length,
        'recorded_at': FieldValue.serverTimestamp(),
        'local_timestamp': timestamp,
        'room_id': _currentRoomId,
        'recorded_by': 'local_user',
      });

      // Clean up the blob URL
      html.Url.revokeObjectUrl(blobUrl);

      print('✅ Video metadata saved to Firestore');
      print('📍 Video Document ID: ${videoDocRef.id}');
      return videoDocRef.id;
    } catch (e) {
      print('❌ Error saving video: $e');
      return null;
    }
  }

  /// Get current room ID
  String? getCurrentRoomId() {
    return _currentRoomId;
  }
}
