import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class FaceSwapWebRtcService {
  FaceSwapWebRtcService(
    this.serverBase, {
    int videoWidth = 720,
    int videoHeight = 1280,
    int videoFps = 24,
  })  : _videoWidth = videoWidth,
        _videoHeight = videoHeight,
        _videoFps = videoFps;

  final String serverBase;

  int _videoWidth;
  int _videoHeight;
  int _videoFps;

  void updateCaptureSettings({
    required int width,
    required int height,
    required int fps,
  }) {
    _videoWidth = width.clamp(320, 1920).toInt();
    _videoHeight = height.clamp(240, 1920).toInt();
    _videoFps = fps.clamp(10, 30).toInt();
  }

  RTCPeerConnection? _pc;

  MediaStream? localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  String? sessionId;

  String state = 'idle';

  void Function(String)? onState;
  void Function(String)? onQualityStats;

  String qualityStats = 'กำลังตรวจสอบคุณภาพวิดีโอ...';
  int _lastInboundBytes = 0;
  DateTime? _lastInboundSample;

  bool _initialized = false;
  bool _disposed = false;

  Timer? _statsTimer;

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    // ห้าม mute ตรงนี้
    // เพราะตอนนี้ localRenderer ยังไม่มี MediaStream
    // จะไป mute หลัง getUserMedia สำเร็จ

    _initialized = true;

    _setState('initialized');
  }

  // ============================================================
  // CONNECT
  // ============================================================

  Future<void> connect() async {
    if (_disposed) {
      throw Exception(
        'FaceSwapWebRtcService already disposed',
      );
    }

    if (!_initialized) {
      await initialize();
    }

    await closePeerOnly();

    _setState(
      'requesting camera/microphone',
    );

    // ==========================================================
    // CAMERA + MICROPHONE
    //
    // เน้นความชัดก่อนต่อ AI
    // 1280x720
    // 24-30 FPS
    // ==========================================================

    final stream = await navigator.mediaDevices.getUserMedia(
      {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'facingMode': 'user',
          'width': {
            'min': _videoWidth,
            'ideal': _videoWidth,
            'max': _videoWidth,
          },
          'height': {
            'min': _videoHeight,
            'ideal': _videoHeight,
            'max': _videoHeight,
          },
          'frameRate': {
            'min': 10,
            'ideal': _videoFps,
            'max': _videoFps,
          },
        },
      },
    );

    localStream = stream;

    localRenderer.srcObject = stream;

    // สำคัญ:
    // ต้อง assign MediaStream ก่อน ถึงจะ mute renderer ได้
    localRenderer.muted = true;

    debugPrint(
      '========================================',
    );
    debugPrint(
      'LOCAL MEDIA READY',
    );
    debugPrint(
      'Audio tracks: ${stream.getAudioTracks().length}',
    );
    debugPrint(
      'Video tracks: ${stream.getVideoTracks().length}',
    );
    debugPrint(
      'Requested camera: ${_videoWidth}x$_videoHeight @ $_videoFps FPS',
    );
    debugPrint(
      '========================================',
    );

    // ==========================================================
    // PEER CONNECTION
    // ==========================================================

    final configuration = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(
      configuration,
    );

    _pc = pc;

    // ==========================================================
    // CONNECTION STATE
    // ==========================================================

    pc.onConnectionState = (
      RTCPeerConnectionState value,
    ) {
      debugPrint(
        'Peer connection state: $value',
      );

      if (value == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState('connected');
        _startStatsMonitor();
        return;
      }

      if (value == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setState('failed');
        return;
      }

      if (value == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setState('disconnected');
        return;
      }

      if (value == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _setState('closed');
        return;
      }

      _setState(
        'peer: ${value.name}',
      );
    };

    // ==========================================================
    // ICE CONNECTION STATE
    // ==========================================================

    pc.onIceConnectionState = (
      RTCIceConnectionState value,
    ) {
      debugPrint(
        'ICE connection state: $value',
      );
    };

    // ==========================================================
    // ICE GATHERING
    // ==========================================================

    pc.onIceGatheringState = (
      RTCIceGatheringState value,
    ) {
      debugPrint(
        'ICE gathering state: $value',
      );
    };

    // ==========================================================
    // ICE CANDIDATE
    // ==========================================================

    pc.onIceCandidate = (
      RTCIceCandidate candidate,
    ) {
      if (candidate.candidate != null) {
        debugPrint(
          'ICE candidate generated',
        );
      }
    };

    // ==========================================================
    // RECEIVE REMOTE AUDIO / VIDEO
    //
    // ห้ามใช้ MediaStream()
    // เพราะ MediaStream เป็น abstract class
    // ==========================================================

    pc.onTrack = (
      RTCTrackEvent event,
    ) async {
      debugPrint(
        'Remote track received: ${event.track.kind}',
      );

      try {
        MediaStream remote;

        if (event.streams.isNotEmpty) {
          remote = event.streams.first;
        } else {
          _remoteStream ??= await createLocalMediaStream(
            'faceswap_remote_stream',
          );

          remote = _remoteStream!;

          final alreadyExists = remote.getTracks().any(
                (item) => item.id == event.track.id,
              );

          if (!alreadyExists) {
            await remote.addTrack(
              event.track,
            );
          }
        }

        _remoteStream = remote;

        remoteRenderer.srcObject = remote;

        debugPrint(
          'Remote ${event.track.kind} attached',
        );

        if (event.track.kind == 'video') {
          remoteRenderer.onFirstFrameRendered = () {
            debugPrint(
              '========================================',
            );
            debugPrint(
              'REMOTE VIDEO FIRST FRAME',
            );
            debugPrint(
              'Resolution: '
              '${remoteRenderer.videoWidth.toInt()}'
              'x'
              '${remoteRenderer.videoHeight.toInt()}',
            );
            debugPrint(
              '========================================',
            );
          };

          remoteRenderer.onResize = () {
            debugPrint(
              'Remote renderer size: '
              '${remoteRenderer.videoWidth.toInt()}'
              'x'
              '${remoteRenderer.videoHeight.toInt()}',
            );
          };
        }
      } catch (error, stackTrace) {
        debugPrint(
          'onTrack error: $error',
        );

        debugPrint(
          '$stackTrace',
        );
      }
    };

    // ==========================================================
    // ADD LOCAL TRACKS
    // ==========================================================

    for (final track in stream.getTracks()) {
      final sender = await pc.addTrack(
        track,
        stream,
      );

      debugPrint(
        'Local track added: ${track.kind}',
      );

      if (track.kind == 'video') {
        await _configureVideoSender(
          sender,
        );
      }
    }

    // ==========================================================
    // CREATE OFFER
    // ==========================================================

    _setState(
      'creating offer',
    );

    final offer = await pc.createOffer(
      {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      },
    );

    await pc.setLocalDescription(
      offer,
    );

    // เราไม่ได้ใช้ trickle ICE
    // รอ ICE gathering ก่อนส่ง SDP ไป Server

    await _waitIceGatheringComplete();

    final localDescription = await pc.getLocalDescription();

    if (localDescription == null || localDescription.sdp == null) {
      throw Exception(
        'Unable to get local SDP',
      );
    }

    // ==========================================================
    // SERVER URL
    // ==========================================================

    var base = serverBase.trim();

    while (base.endsWith('/')) {
      base = base.substring(
        0,
        base.length - 1,
      );
    }

    final offerUrl = Uri.parse(
      '$base/offer',
    );

    debugPrint(
      'POST WebRTC offer: $offerUrl',
    );

    _setState(
      'signaling',
    );

    // ==========================================================
    // POST /offer
    // ==========================================================

    final response = await http
        .post(
          offerUrl,
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'sdp': localDescription.sdp,
            'type': localDescription.type,
          }),
        )
        .timeout(
          const Duration(
            seconds: 45,
          ),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'POST /offer HTTP '
        '${response.statusCode}: '
        '${response.body}',
      );
    }

    // ==========================================================
    // PARSE ANSWER
    // ==========================================================

    final dynamic decoded = jsonDecode(
      response.body,
    );

    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Invalid /offer response',
      );
    }

    final answerSdp = decoded['sdp'];

    final answerType = decoded['type'];

    if (answerSdp is! String || answerType is! String) {
      throw Exception(
        'Server answer does not contain SDP/type',
      );
    }

    sessionId = decoded['session_id']?.toString();

    debugPrint(
      'WebRTC Session ID: $sessionId',
    );

    // ==========================================================
    // APPLY ANSWER
    // ==========================================================

    await pc.setRemoteDescription(
      RTCSessionDescription(
        answerSdp,
        answerType,
      ),
    );

    debugPrint(
      'Remote SDP applied',
    );

    _setState(
      'connected',
    );

    _startStatsMonitor();
  }

  // ============================================================
  // VIDEO QUALITY
  //
  // พยายามบังคับ:
  // - Maintain resolution
  // - 2-5 Mbps
  // - max 30 FPS
  // - ไม่ downscale
  //
  // ถ้า flutter_webrtc / Android รุ่นนั้นไม่รองรับ
  // จะ fallback โดยไม่ทำให้ call ล้ม
  // ============================================================

  Future<void> _configureVideoSender(
    RTCRtpSender sender,
  ) async {
    try {
      final params = sender.parameters;

      params.degradationPreference =
          RTCDegradationPreference.MAINTAIN_RESOLUTION;

      final encodings = params.encodings;

      if (encodings == null || encodings.isEmpty) {
        debugPrint(
          'RTP encoding list empty - '
          'using WebRTC defaults',
        );

        return;
      }

      for (final encoding in encodings) {
        encoding.active = true;

        // Keep facial detail while leaving headroom for three callers.
        encoding.minBitrate = 2200000;

        // A fixed upper bound avoids network queues that look like AI lag.
        encoding.maxBitrate = 4000000;

        encoding.maxFramerate = _videoFps;

        // ไม่ลด resolution
        encoding.scaleResolutionDownBy = 1.0;
      }

      await sender.setParameters(
        params,
      );

      debugPrint(
        '========================================',
      );
      debugPrint(
        'HIGH QUALITY WEBRTC VIDEO',
      );
      debugPrint(
        'Target    : ${_videoWidth}x$_videoHeight',
      );
      debugPrint(
        'FPS       : <= $_videoFps',
      );
      debugPrint(
        'Bitrate   : 2.2-4 Mbps',
      );
      debugPrint(
        'Scale     : 1.0',
      );
      debugPrint(
        'Preference: MAINTAIN_RESOLUTION',
      );
      debugPrint(
        '========================================',
      );
    } catch (error, stackTrace) {
      // ไม่ให้ call พังเพราะ parameter รุ่นมือถือ
      // ไม่รองรับบาง field

      debugPrint(
        'Video RTP config warning: $error',
      );

      debugPrint(
        '$stackTrace',
      );
    }
  }

  // ============================================================
  // WAIT ICE
  // ============================================================

  Future<void> _waitIceGatheringComplete() async {
    final pc = _pc;

    if (pc == null) {
      return;
    }

    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }

    final completer = Completer<void>();

    Timer? timeout;

    pc.onIceGatheringState = (
      RTCIceGatheringState value,
    ) {
      debugPrint(
        'ICE gathering: $value',
      );

      if (value == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    timeout = Timer(
      const Duration(
        seconds: 8,
      ),
      () {
        if (!completer.isCompleted) {
          debugPrint(
            'ICE gathering timeout - '
            'continue with current candidates',
          );

          completer.complete();
        }
      },
    );

    await completer.future;

    timeout.cancel();
  }

  // ============================================================
  // MIC
  // ============================================================

  Future<void> setMic(
    bool enabled,
  ) async {
    final stream = localStream;

    if (stream == null) {
      return;
    }

    final tracks = stream.getAudioTracks();

    for (final track in tracks) {
      track.enabled = enabled;
    }

    debugPrint(
      'Microphone enabled: $enabled',
    );
  }

  // ============================================================
  // CAMERA
  // ============================================================

  Future<void> setCamera(
    bool enabled,
  ) async {
    final stream = localStream;

    if (stream == null) {
      return;
    }

    final tracks = stream.getVideoTracks();

    for (final track in tracks) {
      track.enabled = enabled;
    }

    debugPrint(
      'Camera enabled: $enabled',
    );
  }

  // ============================================================
  // SWITCH CAMERA
  // ============================================================

  Future<void> switchCamera() async {
    final stream = localStream;

    if (stream == null) {
      return;
    }

    final tracks = stream.getVideoTracks();

    if (tracks.isEmpty) {
      return;
    }

    try {
      await Helper.switchCamera(
        tracks.first,
      );

      debugPrint(
        'Camera switched',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Switch camera error: $error',
      );

      debugPrint(
        '$stackTrace',
      );
    }
  }

  // ============================================================
  // STATS
  // ============================================================

  void _startStatsMonitor() {
    _statsTimer?.cancel();

    _statsTimer = Timer.periodic(
      const Duration(
        seconds: 3,
      ),
      (_) async {
        await _printStats();
      },
    );
  }

  Future<void> _printStats() async {
    final pc = _pc;

    if (pc == null) {
      return;
    }

    try {
      debugPrint(
        '============= WEBRTC STATS =============',
      );

      debugPrint(
        'REMOTE VIDEO: '
        '${remoteRenderer.videoWidth.toInt()}'
        'x'
        '${remoteRenderer.videoHeight.toInt()}',
      );

      final senders = await pc.getSenders();

      for (final sender in senders) {
        final track = sender.track;

        if (track == null || track.kind != 'video') {
          continue;
        }

        try {
          final reports = await sender.getStats();

          for (final report in reports) {
            if (report.type == 'outbound-rtp') {
              debugPrint(
                'OUTBOUND VIDEO: ${report.values}',
              );
            }
          }
        } catch (error) {
          debugPrint(
            'Sender stats error: $error',
          );
        }
      }

      final receivers = await pc.getReceivers();

      for (final receiver in receivers) {
        final track = receiver.track;

        if (track == null || track.kind != 'video') {
          continue;
        }

        try {
          final reports = await receiver.getStats();

          for (final report in reports) {
            if (report.type == 'inbound-rtp') {
              final values = report.values;
              final width = (values['frameWidth'] as num?)?.toInt() ??
                  remoteRenderer.videoWidth.toInt();
              final height = (values['frameHeight'] as num?)?.toInt() ??
                  remoteRenderer.videoHeight.toInt();
              final fps = (values['framesPerSecond'] as num?)?.toDouble() ?? 0;
              final lost = (values['packetsLost'] as num?)?.toInt() ?? 0;
              final bytes = (values['bytesReceived'] as num?)?.toInt() ?? 0;
              final now = DateTime.now();
              var mbps = 0.0;
              final previous = _lastInboundSample;
              if (previous != null && bytes >= _lastInboundBytes) {
                final seconds =
                    now.difference(previous).inMilliseconds / 1000.0;
                if (seconds > 0) {
                  mbps = (bytes - _lastInboundBytes) * 8 / seconds / 1000000;
                }
              }
              _lastInboundBytes = bytes;
              _lastInboundSample = now;
              final shortSide = width < height ? width : height;
              final quality = shortSide >= 720 ? 'HD' : 'LOW';
              qualityStats = '$quality  ${width}×$height  '
                  '${fps.toStringAsFixed(0)} FPS  '
                  '${mbps.toStringAsFixed(1)} Mbps  Lost $lost';
              onQualityStats?.call(qualityStats);
              debugPrint(
                'INBOUND VIDEO: ${report.values}',
              );
            }
          }
        } catch (error) {
          debugPrint(
            'Receiver stats error: $error',
          );
        }
      }

      debugPrint(
        '========================================',
      );
    } catch (error) {
      debugPrint(
        'Stats monitor error: $error',
      );
    }
  }

  // ============================================================
  // STATE
  // ============================================================

  void _setState(
    String value,
  ) {
    state = value;

    debugPrint(
      'WebRTC state: $value',
    );

    onState?.call(
      value,
    );
  }

  // ============================================================
  // CLOSE PEER
  // ============================================================

  Future<void> closePeerOnly() async {
    _statsTimer?.cancel();
    _statsTimer = null;

    final pc = _pc;
    _pc = null;

    if (pc != null) {
      try {
        await pc.close();
      } catch (error) {
        debugPrint(
          'Peer close error: $error',
        );
      }
    }

    // ----------------------------------------------------------
    // REMOTE
    // ----------------------------------------------------------

    remoteRenderer.srcObject = null;

    final remote = _remoteStream;

    _remoteStream = null;

    if (remote != null) {
      try {
        for (final track in remote.getTracks()) {
          try {
            track.stop();
          } catch (_) {}
        }

        await remote.dispose();
      } catch (_) {}
    }

    // ----------------------------------------------------------
    // LOCAL
    // ----------------------------------------------------------

    localRenderer.srcObject = null;

    final local = localStream;

    localStream = null;

    if (local != null) {
      try {
        for (final track in local.getTracks()) {
          try {
            track.stop();
          } catch (_) {}
        }

        await local.dispose();
      } catch (_) {}
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _statsTimer?.cancel();
    _statsTimer = null;

    await closePeerOnly();

    if (_initialized) {
      try {
        await localRenderer.dispose();
      } catch (_) {}

      try {
        await remoteRenderer.dispose();
      } catch (_) {}
    }

    _initialized = false;

    _setState(
      'disposed',
    );
  }
}
