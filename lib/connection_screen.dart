import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ConnectionScreen extends StatefulWidget {
  final void Function(String wsUrl, String token) onConnected;

  const ConnectionScreen({
    super.key,
    required this.onConnected,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  static const String defaultServerBase =
      'https://seat-moon-digit-printable.trycloudflare.com';

  final TextEditingController _serverCtrl =
      TextEditingController(text: defaultServerBase);

  final TextEditingController _tokenCtrl = TextEditingController();

  bool _connecting = false;
  String _status = 'Ready';

  @override
  void dispose() {
    _serverCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  String _normalizeBase(String value) {
    var v = value.trim();

    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }

    if (v.startsWith('ws://')) {
      v = 'http://${v.substring(5)}';
    } else if (v.startsWith('wss://')) {
      v = 'https://${v.substring(6)}';
    }

    return v;
  }

  Future<void> _connect() async {
    if (_connecting) return;

    final serverBase = _normalizeBase(_serverCtrl.text);
    final token = _tokenCtrl.text.trim();

    if (serverBase.isEmpty) {
      setState(() => _status = 'Server Base is required');
      return;
    }

    if (token.isEmpty) {
      setState(() => _status = 'Token is required');
      return;
    }

    setState(() {
      _connecting = true;
      _status = 'Checking server...';
    });

    try {
      // 1) Read current server config.
      final configResponse = await http
          .get(
            Uri.parse('$serverBase/v1/client-config'),
          )
          .timeout(const Duration(seconds: 15));

      if (configResponse.statusCode != 200) {
        throw Exception(
          'client-config HTTP ${configResponse.statusCode}',
        );
      }

      final config = jsonDecode(configResponse.body);

      if (config is! Map) {
        throw Exception('Invalid client-config response');
      }

      final sessionCreateUrl =
          (config['session_create_url'] ?? '$serverBase/v1/sessions')
              .toString();

      // 2) Create a fresh session on the real server.
      setState(() => _status = 'Creating session...');

      final sessionResponse = await http
          .post(
            Uri.parse(sessionCreateUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'client_name': 'flutter-mobile',
              'transport': 'ws',
              'resolution': 'mobile',
              'fps': 15,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (sessionResponse.statusCode < 200 ||
          sessionResponse.statusCode >= 300) {
        throw Exception(
          'create session HTTP ${sessionResponse.statusCode}: '
          '${sessionResponse.body}',
        );
      }

      final session = jsonDecode(sessionResponse.body);

      if (session is! Map) {
        throw Exception('Invalid session response');
      }

      final sessionId = (session['session_id'] ?? '').toString();

      if (sessionId.isEmpty) {
        throw Exception('Server did not return session_id');
      }

      // Prefer ws_url returned by session creation.
      // Fall back to /v1/client-config ws_url.
      var wsUrl = (session['ws_url'] ?? config['ws_url'] ?? '').toString();

      if (wsUrl.isEmpty) {
        final uri = Uri.parse(serverBase);
        final scheme = uri.scheme == 'https' ? 'wss' : 'ws';

        wsUrl = uri.replace(
          scheme: scheme,
          path: '/ws',
          queryParameters: {
            'session_id': sessionId,
          },
        ).toString();
      } else {
        final uri = Uri.parse(wsUrl);
        final params = Map<String, String>.from(uri.queryParameters);
        params['session_id'] = sessionId;

        wsUrl = uri
            .replace(
              queryParameters: params,
            )
            .toString();
      }

      if (!mounted) return;

      setState(() {
        _status = 'Connected: $sessionId';
        _connecting = false;
      });

      widget.onConnected(
        wsUrl,
        token,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _connecting = false;
        _status = 'Connect failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'FaceSwap Cam',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 600,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.face_retouching_natural,
                    size: 72,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Connect to FaceSwap Server',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _serverCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server Base',
                      hintText:
                          'https://seat-moon-digit-printable.trycloudflare.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _tokenCtrl,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Server Token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _connecting ? null : _connect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      _connecting ? 'Connecting...' : 'Connect',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Public server:',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SelectableText(
                    defaultServerBase,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
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
