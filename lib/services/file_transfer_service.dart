import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

enum TransferState {
  idle,
  waitingAcceptance,
  connecting,
  transferring,
  completed,
  cancelled,
  failed,
}

class FileTransferService {
  static const String _tokenKey = 'chatapp_jwt';
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int chunkSize = 16 * 1024; // 16KB chunks

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentUserId;
  String? _peerId;
  String? _peerUsername;
  String? _fileName;
  int? _fileSize;
  int _bytesSent = 0;
  File? _selectedFile;
  Uint8List? _receivedData;

  TransferState _state = TransferState.idle;
  Function(TransferState, String?, int?, int?)? onStateChanged;
  Function(double progress)? onProgressChanged;
  Function(Uint8List data, String fileName)? onFileReceived;

  RealtimeChannel? _signalingChannel;
  bool _isInitiator = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      final session = jsonDecode(token) as Map<String, dynamic>;
      final userData = session['user'] as Map<String, dynamic>?;
      _currentUserId = userData?['id'] as String?;
    }
  }

  Future<Future<dynamic> Function()?> pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      final file = File(result.files.single.path!);
      final size = await file.length();

      if (size > maxFileSizeBytes) {
        onStateChanged?.call(TransferState.failed, 'File too large. Max 10MB.', null, null);
        return null;
      }

      _selectedFile = file;
      _fileName = result.files.single.name;
      _fileSize = size;
      _bytesSent = 0;

      return () async {
        if (_currentUserId != null) {
          await _startTransfer();
        }
      };
    }
    return null;
  }

  Future<void> _startTransfer() async {
    if (_peerId == null || _currentUserId == null) return;

    _state = TransferState.waitingAcceptance;
    onStateChanged?.call(_state, 'Waiting for $_peerUsername to accept...', null, null);

    _isInitiator = true;
    await _setupSignaling();
  }

  Future<void> acceptTransfer() async {
    _state = TransferState.connecting;
    onStateChanged?.call(_state, 'Connecting...', null, null);

    _isInitiator = false;
    await _setupPeerConnection();
  }

  Future<void> _setupSignaling() async {
    final channelName = 'file_transfer_${[_currentUserId, _peerId]..sort()}';
    _signalingChannel = _supabase.channel(channelName);

    _signalingChannel!
        .onBroadcast(event: '*', callback: (payload) async {
      final event = payload['event'] as String?;
      final data = payload['payload'] as Map<String, dynamic>?;

      if (data == null) return;
      if (data['sender_id'] == _currentUserId) return;

      switch (event) {
        case 'offer':
          if (!_isInitiator && _state == TransferState.waitingAcceptance) {
            await _handleOffer(data['sdp'] as String);
          }
          break;
        case 'answer':
          if (_isInitiator && _state == TransferState.connecting) {
            await _handleAnswer(data['sdp'] as String);
          }
          break;
        case 'ice_candidate':
          await _handleIceCandidate(data['candidate'] as String, data['sdp_mid'] as String?);
          break;
        case 'transfer_request':
          _peerId = data['sender_id'] as String;
          _peerUsername = data['sender_username'] as String?;
          _fileName = data['file_name'] as String?;
          _fileSize = data['file_size'] as int?;
          _state = TransferState.waitingAcceptance;
          onStateChanged?.call(_state, '$_peerUsername wants to send $_fileName', null, null);
          break;
        case 'transfer_accept':
          _state = TransferState.connecting;
          onStateChanged?.call(_state, 'Connecting...', null, null);
          await _setupPeerConnection();
          await _createOffer();
          break;
        case 'transfer_reject':
          _state = TransferState.cancelled;
          onStateChanged?.call(_state, 'Transfer rejected by $_peerUsername', null, null);
          await _cleanup();
          break;
        case 'transfer_cancel':
          _state = TransferState.cancelled;
          onStateChanged?.call(_state, 'Transfer cancelled by $_peerUsername', null, null);
          await _cleanup();
          break;
      }
    });

    await _signalingChannel!.subscribe((status, error) {
      // Subscribed
    });
  }

  Future<void> sendTransferRequest(String peerId, String peerUsername) async {
    _peerId = peerId;
    _peerUsername = peerUsername;
    await _setupSignaling();

    await _signalingChannel!.sendBroadcastMessage(
      event: 'transfer_request',
      payload: {
        'sender_id': _currentUserId,
        'sender_username': await _getUsername(),
        'file_name': _fileName,
        'file_size': _fileSize,
      },
    );
  }

  Future<void> acceptTransferRequest() async {
    await _signalingChannel!.sendBroadcastMessage(
      event: 'transfer_accept',
      payload: {'sender_id': _currentUserId},
    );
  }

  Future<void> rejectTransferRequest() async {
    await _signalingChannel!.sendBroadcastMessage(
      event: 'transfer_reject',
      payload: {'sender_id': _currentUserId},
    );
    _state = TransferState.cancelled;
    onStateChanged?.call(_state, 'Transfer rejected', null, null);
  }

  Future<void> cancelTransfer() async {
    if (_signalingChannel != null) {
      await _signalingChannel!.sendBroadcastMessage(
        event: 'transfer_cancel',
        payload: {'sender_id': _currentUserId},
      );
    }
    await _cleanup();
    _state = TransferState.cancelled;
    onStateChanged?.call(_state, 'Transfer cancelled', null, null);
  }

  Future<void> _createOffer() async {
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onIceCandidate = (candidate) async {
      await _signalingChannel!.sendBroadcastMessage(
        event: 'ice_candidate',
        payload: {
          'sender_id': _currentUserId,
          'candidate': candidate.toMap(),
          'sdp_mid': candidate.sdpMid,
        },
      );
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _state = TransferState.failed;
        onStateChanged?.call(_state, 'Connection lost', null, null);
        _cleanup();
      }
    };

    _dataChannel = await _peerConnection!.createDataChannel(
      'fileTransfer',
      RTCDataChannelInit()..ordered = true,
    );

    _dataChannel!.onMessage = (message) {
      if (message.isBinary) {
        _handleReceivedChunkBytes(message.binary);
      } else {
        _handleReceivedChunk(message.text);
      }
    };

    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (_isInitiator) {
          _startSendingFile();
        }
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        if (_state == TransferState.transferring) {
          _state = TransferState.failed;
          onStateChanged?.call(_state, 'Connection closed unexpectedly', null, null);
        }
      }
    };

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await _signalingChannel!.sendBroadcastMessage(
      event: 'offer',
      payload: {'sender_id': _currentUserId, 'sdp': offer.toMap()},
    );
  }

  Future<void> _handleOffer(String sdpJson) async {
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onIceCandidate = (candidate) async {
      await _signalingChannel!.sendBroadcastMessage(
        event: 'ice_candidate',
        payload: {
          'sender_id': _currentUserId,
          'candidate': candidate.toMap(),
          'sdp_mid': candidate.sdpMid,
        },
      );
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _state = TransferState.failed;
        onStateChanged?.call(_state, 'Connection lost', null, null);
        _cleanup();
      }
    };

    _dataChannel = await _peerConnection!.createDataChannel(
      'fileTransfer',
      RTCDataChannelInit()..ordered = true,
    );

    _dataChannel!.onMessage = (message) {
      if (message.isBinary) {
        _handleReceivedChunkBytes(message.binary);
      } else {
        _handleReceivedChunk(message.text);
      }
    };

    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _state = TransferState.transferring;
        onStateChanged?.call(_state, 'Receiving $_fileName...', _fileSize, 0);
      }
    };

    await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdpJson, 'offer'));

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _signalingChannel!.sendBroadcastMessage(
      event: 'answer',
      payload: {'sender_id': _currentUserId, 'sdp': answer.toMap()},
    );
  }

  Future<void> _handleAnswer(String sdpJson) async {
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdpJson, 'answer'));
  }

  Future<void> _handleIceCandidate(String candidateJson, String? sdpMid) async {
    final candidateMap = jsonDecode(candidateJson) as Map<String, dynamic>;
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String,
      sdpMid,
      candidateMap['sdpMid'] as int?,
    );
    await _peerConnection!.addCandidate(candidate);
  }

  Future<void> _setupPeerConnection() async {
    // Already set up in _handleOffer
  }

  Future<void> _startSendingFile() async {
    if (_selectedFile == null) return;

    _state = TransferState.transferring;
    onStateChanged?.call(_state, 'Sending $_fileName...', _fileSize, 0);

    try {
      final bytes = await _selectedFile!.readAsBytes();

      int offset = 0;
      while (offset < bytes.length) {
        final end = (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
        final chunk = bytes.sublist(offset, end);

        final messageData = {
          'type': 'file_chunk',
          'data': base64Encode(chunk),
          'fileName': _fileName,
          'fileSize': _fileSize,
          'totalChunks': (bytes.length / chunkSize).ceil(),
          'currentChunk': (offset / chunkSize).floor(),
        };

        _dataChannel!.send(RTCDataChannelMessage(jsonEncode(messageData)));

        _bytesSent = offset + chunk.length;
        final progress = _bytesSent / _fileSize!;
        onProgressChanged?.call(progress);
        onStateChanged?.call(_state, 'Sending $_fileName...', _fileSize, _bytesSent);

        offset = end;

        await Future.delayed(const Duration(milliseconds: 10));
      }

      _state = TransferState.completed;
      onStateChanged?.call(_state, 'File sent successfully!', _fileSize, _bytesSent);
    } catch (e) {
      _state = TransferState.failed;
      onStateChanged?.call(_state, 'Error sending file: $e', null, null);
    }

    await _cleanup();
  }

  void _handleReceivedChunk(String text) {
    try {
      final message = jsonDecode(text) as Map<String, dynamic>;

      if (message['type'] == 'file_chunk') {
        final chunk = base64Decode(message['data'] as String);
        final fileSize = message['fileSize'] as int;
        final currentChunk = message['currentChunk'] as int;
        final totalChunks = message['totalChunks'] as int;

        _receivedData ??= Uint8List(fileSize);
        _receivedData!.setRange(
          currentChunk * chunkSize,
          currentChunk * chunkSize + chunk.length,
          chunk,
        );

        _fileName = message['fileName'] as String?;
        _fileSize = fileSize;

        final progress = (_receivedData!.length) / fileSize;
        onProgressChanged?.call(progress);
        onStateChanged?.call(_state, 'Receiving $_fileName...', fileSize, _receivedData!.length);

        if (currentChunk == totalChunks - 1) {
          _state = TransferState.completed;
          onStateChanged?.call(_state, 'File received!', fileSize, fileSize);
          onFileReceived?.call(_receivedData!, _fileName!);

          _saveReceivedFile(_receivedData!, _fileName!);
          _receivedData = null;
        }
      }
    } catch (e) {
      _state = TransferState.failed;
      onStateChanged?.call(_state, 'Error receiving file: $e', null, null);
    }
  }

  void _handleReceivedChunkBytes(Uint8List bytes) {
    try {
      final message = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      if (message['type'] == 'file_chunk') {
        final chunk = base64Decode(message['data'] as String);
        final fileSize = message['fileSize'] as int;
        final currentChunk = message['currentChunk'] as int;
        final totalChunks = message['totalChunks'] as int;

        _receivedData ??= Uint8List(fileSize);
        _receivedData!.setRange(
          currentChunk * chunkSize,
          currentChunk * chunkSize + chunk.length,
          chunk,
        );

        _fileName = message['fileName'] as String?;
        _fileSize = fileSize;

        final progress = (_receivedData!.length) / fileSize;
        onProgressChanged?.call(progress);
        onStateChanged?.call(_state, 'Receiving $_fileName...', fileSize, _receivedData!.length);

        if (currentChunk == totalChunks - 1) {
          _state = TransferState.completed;
          onStateChanged?.call(_state, 'File received!', fileSize, fileSize);
          onFileReceived?.call(_receivedData!, _fileName!);

          _saveReceivedFile(_receivedData!, _fileName!);
          _receivedData = null;
        }
      }
    } catch (e) {
      _state = TransferState.failed;
      onStateChanged?.call(_state, 'Error receiving file: $e', null, null);
    }
  }

  Future<void> _saveReceivedFile(Uint8List data, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(data);
    } catch (e) {
      // Handle silently
    }
  }

  Future<void> _cleanup() async {
    _dataChannel?.close();
    _dataChannel = null;

    _peerConnection?.close();
    _peerConnection = null;

    await _signalingChannel?.unsubscribe();
    _signalingChannel = null;
  }

  Future<String?> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null) {
      final session = jsonDecode(token) as Map<String, dynamic>;
      return session['user']?['user_metadata']?['username'] as String?;
    }
    return null;
  }

  void reset() {
    _state = TransferState.idle;
    _selectedFile = null;
    _fileName = null;
    _fileSize = null;
    _bytesSent = 0;
    _receivedData = null;
    _peerId = null;
    _peerUsername = null;
    _isInitiator = false;
    _cleanup();
  }

  String? get fileName => _fileName;
  int? get fileSize => _fileSize;
  int get bytesSent => _bytesSent;
  TransferState get state => _state;
  bool get isInitiator => _isInitiator;
}