import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/chat_message_model.dart';
import '../models/profile_model.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';

class ChatScreen extends StatefulWidget {
  final Profile friend;

  const ChatScreen({super.key, required this.friend});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _fileInvitePrefix = '__FILE_SESSION_INVITE__';

  final _chatService = ChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _currentUserId;
  Timer? _refreshTimer;

  bool _showConnectBox = false;
  bool _isWaitingForConnect = false;
  String? _selectedFileName;
  String? _temporarySessionCode;
  OverlayEntry? _copyToastEntry;
  final Set<String> _handledInviteMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadMessages(silent: true),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedFileName = result.files.single.name;
        _temporarySessionCode = _generateTemporarySessionCode();
        _showConnectBox = true;
        _isWaitingForConnect = false;
      });
    }
  }

  String _generateTemporarySessionCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _connectToReceiver() async {
    final code = _temporarySessionCode;
    final fileName = _selectedFileName;
    if (code == null || fileName == null) return;

    final payload = jsonEncode({
      'code': code,
      'fileName': fileName,
      'senderUsername': widget.friend.username,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });

    await _chatService.sendMessage(
      widget.friend.id,
      '$_fileInvitePrefix$payload',
    );
    if (!mounted) return;

    setState(() {
      _isWaitingForConnect = true;
    });
  }

  void _cancelConnectFlow() {
    setState(() {
      _showConnectBox = false;
      _isWaitingForConnect = false;
      _selectedFileName = null;
      _temporarySessionCode = null;
    });
  }

  void _showTopCenterCopyToast() {
    _copyToastEntry?.remove();
    _copyToastEntry = null;

    final overlay = Overlay.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Message copied',
                  style: TextStyle(
                    color: colorScheme.onInverseSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _copyToastEntry = entry;
    overlay.insert(entry);

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _copyToastEntry?.remove();
      _copyToastEntry = null;
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _copyToastEntry?.remove();
    _copyToastEntry = null;
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final currentUserId = await _chatService.currentUserId;
    final messages = await _chatService.getMessages(widget.friend.id);
    if (!mounted) return;
    if (silent) {
      if (messages.length != _messages.length) {
        setState(() {
          _messages = messages;
          _currentUserId = currentUserId;
        });
      }
    } else {
      setState(() {
        _messages = messages;
        _isLoading = false;
        _currentUserId = currentUserId;
      });
    }
    _checkIncomingFileInvite(messages, currentUserId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    await _chatService.sendMessage(widget.friend.id, text);
    if (!mounted) return;

    setState(() => _isSending = false);
    _loadMessages(silent: true);
  }

  Future<void> _showMessageActions(ChatMessage msg) async {
    final colorScheme = Theme.of(context).colorScheme;
    final contentToCopy = _displayMessageContent(msg);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: contentToCopy));
                  if (!mounted) return;
                  Navigator.of(sheetContext).pop();
                  _showTopCenterCopyToast();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isMe = msg.isMe(_currentUserId ?? '');
    final colorScheme = Theme.of(context).colorScheme;
    final displayText = _displayMessageContent(msg);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(msg),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          decoration: BoxDecoration(
            color: isMe
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: isMe
                  ? const Radius.circular(18)
                  : const Radius.circular(4),
              bottomRight: isMe
                  ? const Radius.circular(4)
                  : const Radius.circular(18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayText,
                style: TextStyle(
                  fontSize: 15,
                  color: isMe
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(msg.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color:
                      (isMe
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface)
                          .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _tryParseInvite(ChatMessage msg) {
    if (!msg.content.startsWith(_fileInvitePrefix)) {
      return null;
    }

    final rawPayload = msg.content.substring(_fileInvitePrefix.length);
    try {
      final payload = jsonDecode(rawPayload);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _displayMessageContent(ChatMessage msg) {
    final payload = _tryParseInvite(msg);
    if (payload == null) return msg.content;

    final fileName = (payload['fileName'] as String?) ?? 'file';
    final code = (payload['code'] as String?) ?? 'N/A';
    final isMine = msg.isMe(_currentUserId ?? '');

    if (isMine) {
      return 'You sent a file invite for "$fileName". Session code: $code';
    }

    return 'File invite received for "$fileName". Session code: $code';
  }

  void _checkIncomingFileInvite(
    List<ChatMessage> messages,
    String? currentUserId,
  ) {
    if (currentUserId == null) return;

    ChatMessage? latestInvite;
    Map<String, dynamic>? latestPayload;

    for (final msg in messages.reversed) {
      if (msg.senderId == currentUserId) continue;
      if (_handledInviteMessageIds.contains(msg.id)) continue;

      final payload = _tryParseInvite(msg);
      if (payload == null) continue;

      latestInvite = msg;
      latestPayload = payload;
      break;
    }

    if (latestInvite == null || latestPayload == null) return;

    _handledInviteMessageIds.add(latestInvite.id);

    final fileName = (latestPayload['fileName'] as String?) ?? 'file';
    final code = (latestPayload['code'] as String?) ?? 'N/A';

    NotificationService().showNewMessageNotification(
      widget.friend.username,
      'File invite received for "$fileName". Code: $code',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final colorScheme = Theme.of(dialogContext).colorScheme;

          return AlertDialog(
            title: const Text('File Transfer Invitation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${widget.friend.username} invited you to receive a file.',
                ),
                const SizedBox(height: 10),
                Text('File: $fileName'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Session code: $code',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Dismiss'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  setState(() {
                    _showConnectBox = true;
                    _isWaitingForConnect = true;
                    _selectedFileName = fileName;
                    _temporarySessionCode = code;
                  });
                },
                child: const Text('Open Invite'),
              ),
            ],
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: widget.friend.avatarUrl != null
                  ? NetworkImage(widget.friend.avatarUrl!)
                  : null,
              child: widget.friend.avatarUrl == null
                  ? Text(
                      widget.friend.username[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${widget.friend.username}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'Say hi to @${widget.friend.username}!',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildMessageBubble(_messages[i]),
                  ),
          ),
          if (_showConnectBox) _buildConnectBox(colorScheme),
          Container(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _pickFile,
                  icon: Icon(Icons.attach_file, color: colorScheme.primary),
                  tooltip: 'Send file',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Message @${widget.friend.username}...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectBox(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isWaitingForConnect ? Icons.hourglass_empty : Icons.link,
                color: _isWaitingForConnect
                    ? colorScheme.tertiary
                    : colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isWaitingForConnect
                          ? 'Waiting for receiver to connect'
                          : 'File selected: ${_selectedFileName ?? 'Unknown file'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (_temporarySessionCode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Session code: $_temporarySessionCode',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _cancelConnectFlow,
                child: const Text('Cancel'),
              ),
            ],
          ),
          if (_isWaitingForConnect)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Share this temporary session code with your receiver to connect securely.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_isWaitingForConnect)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.icon(
                  onPressed: _connectToReceiver,
                  icon: const Icon(Icons.link),
                  label: const Text('Connect'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
