import 'package:flutter/material.dart';
import '../models/friend_model.dart';
import '../services/friend_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _friendService = FriendService();

  List<FriendRequest> _received = [];
  List<FriendRequest> _sent = [];
  List<FriendRequest> _accepted = [];
  List<Friend> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _friendService.getReceivedRequests(),
      _friendService.getSentRequests(),
      _friendService.getAcceptedRequests(),
      _friendService.getFriends(),
    ]);
    if (mounted) {
      setState(() {
        _received = results[0] as List<FriendRequest>;
        _sent = results[1] as List<FriendRequest>;
        _accepted = results[2] as List<FriendRequest>;
        _friends = results[3] as List<Friend>;
        _isLoading = false;
      });
    }
  }

  Future<void> _accept(String requestId) async {
    await _friendService.acceptRequest(requestId);
    _loadAll();
  }

  Future<void> _reject(String requestId) async {
    await _friendService.rejectRequest(requestId);
    _loadAll();
  }

  Future<void> _cancel(String requestId) async {
    await _friendService.cancelRequest(requestId);
    _loadAll();
  }

  Future<void> _unfriend(String friendId) async {
    await _friendService.unfriend(friendId);
    _loadAll();
  }

  Widget _buildAvatar(String? avatarUrl, String initial, {double radius = 24}) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
      child: avatarUrl == null
          ? Text(
              initial[0].toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );
  }

  Widget _buildReceivedCard(FriendRequest req) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _buildAvatar(req.senderAvatarUrl, req.senderUsername ?? 'U'),
        title: Text('@${req.senderUsername ?? 'Unknown'}'),
        subtitle: const Text('wants to be your friend'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _reject(req.id),
              child: Text(
                'Reject',
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _accept(req.id),
              child: const Text(
                'Accept',
                style: TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentCard(FriendRequest req) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _buildAvatar(req.receiverAvatarUrl, req.receiverUsername ?? 'U'),
        title: Text('@${req.receiverUsername ?? 'Unknown'}'),
        subtitle: const Text('request sent'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _cancel(req.id),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(Friend friend) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _buildAvatar(friend.friendAvatarUrl, friend.friendUsername ?? 'U'),
        title: Text('@${friend.friendUsername ?? 'Unknown'}'),
        subtitle: const Text('friend'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => _unfriend(friend.friendId),
              child: Text(
                'Remove',
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptedCard(FriendRequest req, String friendId, String? friendUsername, String? friendAvatarUrl) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _buildAvatar(friendAvatarUrl, friendUsername ?? 'U'),
        title: Text('@${friendUsername ?? 'Unknown'}'),
        subtitle: const Text('friend'),
        trailing: Icon(Icons.chat_bubble_outline, color: colorScheme.primary),
      ),
    );
  }

  Widget _buildEmpty(String message, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 56,
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceivedList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_received.isEmpty) return _buildEmpty('No received requests', Icons.inbox);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _received.length,
      itemBuilder: (_, i) => _buildReceivedCard(_received[i]),
    );
  }

  Widget _buildSentList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_sent.isEmpty) return _buildEmpty('No sent requests', Icons.send);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _sent.length,
      itemBuilder: (_, i) => _buildSentCard(_sent[i]),
    );
  }

  Widget _buildAcceptedList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_accepted.isEmpty) return _buildEmpty('No accepted requests', Icons.check_circle);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _accepted.length,
      itemBuilder: (_, i) {
        final req = _accepted[i];
        final friendId = req.senderId;
        final friendUsername = req.senderUsername;
        final friendAvatarUrl = req.senderAvatarUrl;
        return _buildAcceptedCard(req, friendId, friendUsername, friendAvatarUrl);
      },
    );
  }

  Widget _buildFriendsList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_friends.isEmpty) return _buildEmpty('No friends yet', Icons.person_add);
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _friends.length,
        itemBuilder: (_, i) => _buildFriendCard(_friends[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'Friends (${_friends.length})'),
            Tab(text: 'Received (${_received.length})'),
            Tab(text: 'Sent (${_sent.length})'),
            Tab(text: 'Accepted (${_accepted.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsList(),
          _buildReceivedList(),
          _buildSentList(),
          _buildAcceptedList(),
        ],
      ),
    );
  }
}