import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Signaling {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  RTCVideoRenderer? _remoteRenderer;

  Function(MediaStream stream)? onAddRemoteStream;

  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  // ** Open user media (camera + mic) and bind to localRenderer
  Future<void> openUserMedia(RTCVideoRenderer localRenderer, RTCVideoRenderer remoteRenderer) async {
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
  Future<String?> createRoom(RTCVideoRenderer remoteRenderer) async {
    _remoteRenderer = remoteRenderer;
    DocumentReference roomRef = _firestore.collection('rooms').doc();

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
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

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
        peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
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
}