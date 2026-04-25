import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile_model.dart';
import '../services/friend_service.dart';

class ProfileViewScreen extends StatefulWidget {
  final Profile profile;

  const ProfileViewScreen({super.key, required this.profile});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  final _friendService = FriendService();
  String? _requestStatus;
  bool _isLoading = false;
  bool _isCurrentUser = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
    _checkStatus();
  }

  Future<void> _checkCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('chatapp_jwt');
    if (token != null) {
      try {
        final session = jsonDecode(token) as Map<String, dynamic>;
        final userData = session['user'] as Map<String, dynamic>?;
        final userId = userData?['id'] as String?;
        if (mounted) {
          setState(() {
            _isCurrentUser = userId == widget.profile.id;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _checkStatus() async {
    final status = await _friendService.checkRequestStatus(widget.profile.id);
    if (mounted) setState(() => _requestStatus = status);
  }

  Future<void> _sendRequest() async {
    setState(() => _isLoading = true);
    final error = await _friendService.sendFriendRequest(widget.profile.id);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (error != null) {
      _showError(error);
    } else {
      setState(() => _requestStatus = 'pending');
      _showSuccess('Friend request sent to @${widget.profile.username}!');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  String _buttonLabel() {
    if (_isCurrentUser) return 'This is you';
    switch (_requestStatus) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Friends';
      case 'rejected':
        return 'Add Friend';
      default:
        return 'Add Friend';
    }
  }

  bool _isDisabled() {
    if (_isCurrentUser) return true;
    return _requestStatus == 'pending' || _requestStatus == 'accepted';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.profile.username}'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 60,
                backgroundColor: colorScheme.primaryContainer,
                backgroundImage: widget.profile.avatarUrl != null
                    ? NetworkImage(widget.profile.avatarUrl!)
                    : null,
                child: widget.profile.avatarUrl == null
                    ? Text(
                        widget.profile.username[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                '@${widget.profile.username}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading || _isDisabled() ? null : _sendRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _requestStatus == 'accepted'
                        ? colorScheme.secondaryContainer
                        : colorScheme.primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _buttonLabel(),
                          style: TextStyle(
                            fontSize: 16,
                            color: _isDisabled()
                                ? colorScheme.onSurface.withValues(alpha: 0.5)
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
