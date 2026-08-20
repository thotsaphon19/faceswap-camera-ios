import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'webrtc_service.dart';

const String defaultServer =
    'https://seat-moon-digit-printable.trycloudflare.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await WakelockPlus.enable();
  } catch (_) {}

  runApp(
    const FaceSwapApp(),
  );
}

// ============================================================
// APP
// ============================================================

class FaceSwapApp extends StatelessWidget {
  const FaceSwapApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FaceSwap Realtime v4',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(
          0xFF090B10,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(
            0xFF6750A4,
          ),
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectPage(),
    );
  }
}

// ============================================================
// CONNECT PAGE
// ============================================================

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
  });

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final TextEditingController _serverController = TextEditingController(
    text: defaultServer,
  );

  String _status = 'Ready';

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _loadSettings();
  }

  // ==========================================================
  // LOAD SERVER
  // ==========================================================

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final saved = prefs.getString(
        'webrtc_server',
      );

      if (saved != null && saved.trim().isNotEmpty) {
        _serverController.text = saved.trim();
      }
    } catch (_) {}
  }

  // ==========================================================
  // NORMALIZE URL
  // ==========================================================

  String _serverBase() {
    var value = _serverController.text.trim();

    while (value.endsWith('/')) {
      value = value.substring(
        0,
        value.length - 1,
      );
    }

    return value;
  }

  // ==========================================================
  // HEALTH + OPEN CALL
  // ==========================================================

  Future<void> _connect() async {
    if (_busy) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _status = 'Checking GPU Server...';
    });

    try {
      final base = _serverBase();

      if (base.isEmpty) {
        throw Exception(
          'Server URL is empty',
        );
      }

      final healthUrl = Uri.parse(
        '$base/health',
      );

      final response = await http
          .get(
            healthUrl,
          )
          .timeout(
            const Duration(
              seconds: 15,
            ),
          );

      if (response.statusCode != 200) {
        throw Exception(
          'Health HTTP '
          '${response.statusCode}',
        );
      }

      final dynamic decoded = jsonDecode(
        response.body,
      );

      if (decoded is! Map) {
        throw Exception(
          'Invalid health response',
        );
      }

      if (decoded['status'] != 'ok') {
        throw Exception(
          'Server status is not OK',
        );
      }

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'webrtc_server',
        base,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Server Ready';
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallPage(
            serverBase: base,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _busy = false;
        _status = 'Ready';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _busy = false;

        _status = 'Connect failed:\n'
            '$error';
      });
    }
  }

  @override
  void dispose() {
    _serverController.dispose();

    super.dispose();
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(
              24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 620,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    height: 20,
                  ),

                  // ==================================================
                  // LOGO
                  // ==================================================

                  Container(
                    width: 92,
                    height: 92,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(
                        0xFF241A38,
                      ),
                      border: Border.all(
                        color: const Color(
                          0xFF7656C7,
                        ),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.face_retouching_natural,
                      size: 52,
                    ),
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  const Text(
                    'FaceSwap Realtime v4',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  const Text(
                    'WebRTC Camera + Microphone',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(
                    height: 32,
                  ),

                  // ==================================================
                  // SERVER URL
                  // ==================================================

                  TextField(
                    controller: _serverController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'GPU Server URL',
                      hintText: defaultServer,
                      prefixIcon: Icon(
                        Icons.cloud,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  // ==================================================
                  // CONNECT BUTTON
                  // ==================================================

                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.link,
                            ),
                      label: Text(
                        _busy ? 'Connecting...' : 'Connect WebRTC',
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  // ==================================================
                  // STATUS
                  // ==================================================

                  Container(
                    padding: const EdgeInsets.all(
                      14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: 0.06,
                      ),
                      borderRadius: BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: SelectableText(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 22,
                  ),

                  const Text(
                    'ขั้นนี้ทดสอบ WebRTC แบบตรงก่อนต่อ '
                    'LivePortrait / Identity / Lip Sync / Occlusion',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(
                    height: 30,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CALL PAGE
// ============================================================

class CallPage extends StatefulWidget {
  final String serverBase;

  const CallPage({
    super.key,
    required this.serverBase,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final FaceSwapWebRtcService rtc;

  final ImagePicker _imagePicker = ImagePicker();

  Uint8List? _sourcePreview;
  bool _sourceReady = false;
  bool _uploadingSource = false;
  String _sourceStatus = 'ยังไม่ได้เลือกใบหน้า';

  String _qualityResolution = '720p';
  int _qualityFps = 24;
  double _imageSharpen = 0.22;
  double _faceSharpen = 0.46;
  double _edgeBlend = 0.78;
  double _mouthPreserve = 0.34;
  int _audioOffsetMs = 0;
  int _detectInterval = 2;
  bool _applyingQuality = false;
  bool _showQualityStats = true;
  String _qualityStats = 'กำลังตรวจสอบคุณภาพวิดีโอ...';

  String _state = 'initializing';

  bool _micEnabled = true;
  bool _cameraEnabled = true;

  bool _starting = true;

  @override
  void initState() {
    super.initState();

    rtc = FaceSwapWebRtcService(
      widget.serverBase,
    );

    rtc.onState = (
      String value,
    ) {
      if (!mounted) {
        return;
      }

      setState(() {
        _state = value;

        if (value == 'connected' ||
            value.contains(
              'Connected',
            )) {
          _starting = false;
        }
      });
    };

    rtc.onQualityStats = (value) {
      if (!mounted) return;
      setState(() => _qualityStats = value);
    };

    _start();
  }

  // ==========================================================
  // START WEBRTC
  // ==========================================================

  Future<void> _start() async {
    try {
      await _loadQualitySettings();

      final size = _resolutionSize(_qualityResolution);
      rtc.updateCaptureSettings(
        width: size.$1,
        height: size.$2,
        fps: _qualityFps,
      );

      await rtc.initialize();

      await rtc.connect();

      if (!mounted) {
        return;
      }

      setState(() {
        _starting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _starting = false;

        _state = 'ERROR:\n$error';
      });
    }
  }

  (int, int) _resolutionSize(String value) {
    switch (value) {
      case '480p':
        return (480, 854);
      case '1080p':
        return (1080, 1920);
      default:
        return (720, 1280);
    }
  }

  Future<void> _loadQualitySettings() async {
    final prefs = await SharedPreferences.getInstance();
    _qualityResolution = prefs.getString('quality_resolution') ?? '720p';
    _qualityFps = prefs.getInt('quality_fps') ?? 24;
    // Migrate the former 15 FPS default; users can still select another FPS
    // explicitly after the first upgraded connection.
    if (_qualityFps == 15) _qualityFps = 24;
    _imageSharpen = prefs.getDouble('quality_image_sharpen') ?? 0.22;
    _faceSharpen = prefs.getDouble('quality_sharpen') ?? 0.46;
    _edgeBlend = prefs.getDouble('quality_edge_blend') ?? 0.78;
    _mouthPreserve = prefs.getDouble('quality_mouth') ?? 0.34;
    _audioOffsetMs = prefs.getInt('quality_audio_offset') ?? 0;
    _detectInterval = prefs.getInt('quality_detect_interval') ?? 3;
  }

  Future<void> _applyQualitySettings() async {
    if (_applyingQuality) return;
    setState(() => _applyingQuality = true);

    try {
      final response = await http
          .post(
            Uri.parse('${widget.serverBase}/v1/settings'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image_sharpen': _imageSharpen,
              'face_sharpen': _faceSharpen,
              'edge_blend': _edgeBlend,
              'mouth_preserve': _mouthPreserve,
              'detect_interval': _detectInterval,
              'audio_offset_ms': _audioOffsetMs,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Settings HTTP ${response.statusCode}: ${response.body}');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('quality_resolution', _qualityResolution);
      await prefs.setInt('quality_fps', _qualityFps);
      await prefs.setDouble('quality_image_sharpen', _imageSharpen);
      await prefs.setDouble('quality_sharpen', _faceSharpen);
      await prefs.setDouble('quality_edge_blend', _edgeBlend);
      await prefs.setDouble('quality_mouth', _mouthPreserve);
      await prefs.setInt('quality_audio_offset', _audioOffsetMs);
      await prefs.setInt('quality_detect_interval', _detectInterval);

      final size = _resolutionSize(_qualityResolution);
      rtc.updateCaptureSettings(
        width: size.$1,
        height: size.$2,
        fps: _qualityFps,
      );

      // Capture constraints and the fixed A/V offset take effect on a fresh
      // peer. The server keeps the uploaded source face in memory.
      await rtc.connect();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ใช้การตั้งค่าคุณภาพใหม่แล้ว')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ตั้งค่าไม่สำเร็จ: $error'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingQuality = false);
    }
  }

  Future<void> _openQualitySettings() async {
    var resolution = _qualityResolution;
    var fps = _qualityFps.toDouble();
    var imageSharpen = _imageSharpen;
    var sharpen = _faceSharpen;
    var edgeBlend = _edgeBlend;
    var mouth = _mouthPreserve;
    var audio = _audioOffsetMs.toDouble();
    var detect = _detectInterval.toDouble();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15151A),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ปรับแต่งคุณภาพ Face Swap',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  value: resolution,
                  decoration: const InputDecoration(
                    labelText: 'ความละเอียดกล้อง',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '480p', child: Text('480p — เร็ว')),
                    DropdownMenuItem(value: '720p', child: Text('720p — แนะนำ')),
                    DropdownMenuItem(value: '1080p', child: Text('1080p — คมสูง/ใช้ GPU มาก')),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => resolution = value);
                  },
                ),
                _qualitySlider(
                  label: 'FPS',
                  valueText: '${fps.round()} FPS',
                  value: fps,
                  min: 10,
                  max: 30,
                  divisions: 20,
                  onChanged: (value) => setSheetState(() => fps = value),
                ),
                _qualitySlider(
                  label: 'ความคมทั้งภาพ — ระดับที่ 1',
                  valueText: '${(imageSharpen * 100).round()}%',
                  value: imageSharpen,
                  min: 0,
                  max: 0.50,
                  divisions: 25,
                  onChanged: (value) =>
                      setSheetState(() => imageSharpen = value),
                ),
                _qualitySlider(
                  label: 'ความคมใบหน้า — ระดับที่ 2',
                  valueText: '${(sharpen * 100).round()}%',
                  value: sharpen,
                  min: 0,
                  max: 1.25,
                  divisions: 25,
                  onChanged: (value) => setSheetState(() => sharpen = value),
                ),
                _qualitySlider(
                  label: 'ความเนียนขอบหน้า / ลดเงาดำ',
                  valueText: '${(edgeBlend * 100).round()}%',
                  value: edgeBlend,
                  min: 0,
                  max: 1.0,
                  divisions: 20,
                  onChanged: (value) =>
                      setSheetState(() => edgeBlend = value),
                ),
                _qualitySlider(
                  label: 'รักษารูปปากจริง',
                  valueText: '${(mouth * 100).round()}%',
                  value: mouth,
                  min: 0,
                  max: 0.75,
                  divisions: 15,
                  onChanged: (value) => setSheetState(() => mouth = value),
                ),
                _qualitySlider(
                  label: 'ชดเชยเสียงกับภาพ',
                  valueText: '${audio.round()} ms',
                  value: audio,
                  min: -250,
                  max: 250,
                  divisions: 50,
                  onChanged: (value) => setSheetState(() => audio = value),
                ),
                const Text(
                  'ค่าบวก = เสียงช้าลง • ค่าลบ = ภาพช้าลง',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                _qualitySlider(
                  label: 'ตรวจจับใบหน้าทุกกี่เฟรม',
                  valueText: '${detect.round()} เฟรม',
                  value: detect,
                  min: 1,
                  max: 6,
                  divisions: 5,
                  onChanged: (value) => setSheetState(() => detect = value),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setSheetState(() {
                    resolution = '720p';
                    fps = 15;
                    imageSharpen = 0.22;
                    sharpen = 0.46;
                    edgeBlend = 0.78;
                    mouth = 0.34;
                    audio = 0;
                    detect = 3;
                  }),
                  child: const Text('คืนค่าแนะนำ'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _qualityResolution = resolution;
                      _qualityFps = fps.round();
                      _imageSharpen = imageSharpen;
                      _faceSharpen = sharpen;
                      _edgeBlend = edgeBlend;
                      _mouthPreserve = mouth;
                      _audioOffsetMs = audio.round();
                      _detectInterval = detect.round();
                    });
                    Navigator.of(sheetContext).pop();
                    _applyQualitySettings();
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('บันทึกและใช้งาน'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qualitySlider({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text(valueText)],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // MIC
  // ==========================================================

  Future<void> _toggleMic() async {
    _micEnabled = !_micEnabled;

    await rtc.setMic(
      _micEnabled,
    );

    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // CAMERA
  // ==========================================================

  Future<void> _toggleCamera() async {
    _cameraEnabled = !_cameraEnabled;

    await rtc.setCamera(
      _cameraEnabled,
    );

    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // SWITCH CAMERA
  // ==========================================================

  Future<void> _switchCamera() async {
    try {
      await rtc.switchCamera();
    } catch (_) {}
  }

  // ==========================================================
  // SELECT + UPLOAD SOURCE FACE
  // ==========================================================

  Future<void> _pickAndUploadSourceFace() async {
    if (_uploadingSource) {
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 95,
        requestFullMetadata: false,
      );

      if (picked == null) {
        return;
      }

      final bytes = await picked.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('ไฟล์รูปภาพว่างเปล่า');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _sourcePreview = bytes;
        _sourceReady = false;
        _uploadingSource = true;
        _sourceStatus = 'กำลังอัปโหลดใบหน้า...';
      });

      final session = rtc.sessionId?.trim();
      final sessionId = session == null || session.isEmpty
          ? 'flutter-mobile'
          : session;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${widget.serverBase}/v1/sessions/'
          '${Uri.encodeComponent(sessionId)}/source',
        ),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: picked.name.isEmpty ? 'source_face.jpg' : picked.name,
        ),
      );

      final streamed = await request.send().timeout(
            const Duration(seconds: 45),
          );

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Upload HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! Map || decoded['source_ready'] != true) {
        throw Exception('Server ไม่ยืนยัน source_ready');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _sourceReady = true;
        _uploadingSource = false;
        _sourceStatus = 'Source Face พร้อมใช้งาน';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('อัปโหลดใบหน้าสำเร็จ เริ่ม Face Swap แล้ว'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _sourceReady = false;
        _uploadingSource = false;
        _sourceStatus = 'อัปโหลดไม่สำเร็จ';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('อัปโหลดใบหน้าไม่สำเร็จ: $error'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  // ==========================================================
  // END CALL
  // ==========================================================

  Future<void> _endCall() async {
    try {
      await rtc.dispose();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    rtc.dispose();

    super.dispose();
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,

      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'FaceSwap v4 Test',
        ),
        actions: [
          IconButton(
            tooltip: 'แสดงคุณภาพวิดีโอ',
            onPressed: () => setState(
              () => _showQualityStats = !_showQualityStats,
            ),
            icon: Icon(
              _showQualityStats ? Icons.hd : Icons.hd_outlined,
            ),
          ),
          IconButton(
            tooltip: 'ตั้งค่าคุณภาพ',
            onPressed: _applyingQuality ? null : _openQualitySettings,
            icon: _applyingQuality
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: _sourceReady ? 'เปลี่ยนใบหน้า' : 'เลือกใบหน้า',
            onPressed: _uploadingSource ? null : _pickAndUploadSourceFace,
            icon: _uploadingSource
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _sourceReady
                        ? Icons.face_retouching_natural
                        : Icons.add_photo_alternate,
                    color: _sourceReady ? Colors.greenAccent : Colors.white,
                  ),
          ),
          IconButton(
            tooltip: 'Switch Camera',
            onPressed: _switchCamera,
            icon: const Icon(
              Icons.cameraswitch,
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ==================================================
            // REMOTE VIDEO
            //
            // IMPORTANT:
            // Cover = ภาพเต็มจอ
            // ไม่เหลือวิดีโอเล็กตรงกลาง
            // ==================================================

            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: RTCVideoView(
                  rtc.remoteRenderer,

                  // ภาพจาก Server
                  // ให้เต็มหน้าจอ
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,

                  // Remote result ปกติไม่จำเป็นต้อง mirror
                  mirror: false,
                ),
              ),
            ),

            if (_showQualityStats)
              Positioned(
                left: 10,
                top: 10,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      _qualityStats,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

            // ==================================================
            // WAITING OVERLAY
            // ==================================================

            if (_starting)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(
                        height: 16,
                      ),
                      Text(
                        'Connecting WebRTC...',
                      ),
                    ],
                  ),
                ),
              ),

            // ==================================================
            // LOCAL PREVIEW
            // ==================================================

            Positioned(
              left: 14,
              top: 14,
              width: 104,
              height: 142,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap:
                      _uploadingSource ? null : _pickAndUploadSourceFace,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _sourceReady
                            ? Colors.greenAccent
                            : Colors.white38,
                        width: 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_sourcePreview != null)
                          Image.memory(
                            _sourcePreview!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        else
                          const Center(
                            child: Icon(
                              Icons.add_photo_alternate,
                              size: 36,
                              color: Colors.white70,
                            ),
                          ),
                        if (_uploadingSource)
                          Container(
                            color: Colors.black54,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black87,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 5,
                            ),
                            child: Text(
                              _sourceReady ? 'FACE READY' : 'SELECT FACE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _sourceReady
                                    ? Colors.greenAccent
                                    : Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              right: 14,
              top: 14,
              width: 118,
              height: 170,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                  border: Border.all(
                    color: Colors.white30,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.45,
                      ),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
                  child: RTCVideoView(
                    rtc.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

            // ==================================================
            // STATUS
            // ==================================================

            Positioned(
              left: 12,
              right: 12,
              bottom: 100,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(
                    alpha: 0.55,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'State: $_state',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      'Session: '
                      '${rtc.sessionId ?? '-'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      'Face: $_sourceStatus',
                      style: TextStyle(
                        fontSize: 11,
                        color: _sourceReady
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ==================================================
            // CALL CONTROLS
            // ==================================================

            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // SOURCE FACE

                    _CallButton(
                      icon: _sourceReady
                          ? Icons.face_retouching_natural
                          : Icons.add_photo_alternate,
                      active: _sourceReady,
                      busy: _uploadingSource,
                      onTap: _pickAndUploadSourceFace,
                    ),

                    // MIC

                    _CallButton(
                      icon: _micEnabled ? Icons.mic : Icons.mic_off,
                      active: _micEnabled,
                      onTap: _toggleMic,
                    ),

                    // CAMERA

                    _CallButton(
                      icon:
                          _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                      active: _cameraEnabled,
                      onTap: _toggleCamera,
                    ),

                    // SWITCH

                    _CallButton(
                      icon: Icons.cameraswitch,
                      active: true,
                      onTap: _switchCamera,
                    ),

                    // END

                    _CallButton(
                      icon: Icons.call_end,
                      active: true,
                      danger: true,
                      onTap: _endCall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CALL BUTTON
// ============================================================

class _CallButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool danger;
  final VoidCallback onTap;
  final bool busy;

  const _CallButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.danger = false,
    this.busy = false,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final background = danger
        ? Colors.red
        : active
            ? const Color(
                0xFF4C3A78,
              )
            : const Color(
                0xFF292929,
              );

    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 58,
          height: 58,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  icon,
                  size: 27,
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}
