import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/friend_service.dart';
import '../services/notification_service.dart';
import '../models/friend_model.dart';
import '../models/profile_model.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showedWelcome = false;
  final _friendService = FriendService();
  List<Friend> _friends = [];
  int _pendingCount = 0;
  bool _isLoadingFriends = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_showedWelcome) {
      _showedWelcome = true;
      final username =
          Provider.of<AuthProvider>(context, listen: false)
              .currentUser?.username ??
              'User';
      NotificationService().showWelcomeBackNotification(username);
    }
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final results = await Future.wait([
      _friendService.getFriends(),
      _friendService.getReceivedRequests(),
    ]);
    if (mounted) {
      setState(() {
        _friends = results[0] as List<Friend>;
        _pendingCount = (results[1] as List).length;
        _isLoadingFriends = false;
      });
    }
  }

  Widget _buildAvatar(String? avatarUrl, String initial, {double radius = 20}) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
      child: avatarUrl == null
          ? Text(
              initial[0].toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.7,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final username = authProvider.currentUser?.username ?? 'User';
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Users',
            onPressed: () => Navigator.pushNamed(context, '/search'),
          ),
          IconButton(
            icon: Badge(
              label: Text('$_pendingCount'),
              isLabelVisible: _pendingCount > 0,
              child: const Icon(Icons.person_add),
            ),
            tooltip: 'Friends',
            onPressed: () async {
              await Navigator.pushNamed(context, '/friends');
              _loadFriends();
            },
          ),
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () => themeProvider.toggleTheme(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await authProvider.logout();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.red[700])),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadFriends(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Image.asset('app_logo.png', width: 60, height: 60),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome, @$username!',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Friends',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (!_isLoadingFriends)
                      Text(
                        '${_friends.length} friends',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_isLoadingFriends)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_friends.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.person_add,
                          size: 48,
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No friends yet',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search for users to add friends',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final friend = _friends[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: _buildAvatar(
                            friend.friendAvatarUrl, friend.friendUsername ?? 'U'),
                        title: Text('@${friend.friendUsername ?? 'Unknown'}'),
                        trailing: Icon(
                          Icons.chat_bubble_outline,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        onTap: () async {
                          final profile = Profile(
                            id: friend.friendId,
                            username: friend.friendUsername ?? 'Unknown',
                            avatarUrl: friend.friendAvatarUrl,
                          );
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(friend: profile),
                            ),
                          );
                          _loadFriends();
                        },
                      ),
                    );
                  },
                  childCount: _friends.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}