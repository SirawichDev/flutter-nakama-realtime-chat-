import 'dart:async';
import 'package:flutter/material.dart';
import '../services/nakama_service.dart';
import 'private_chat_screen.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final NakamaService _nakamaService = NakamaService();
  bool _isLoading = false;
  bool _isConnected = false;
  String? _currentUsername;
  List<Map<String, String>> _users = [];
  StreamSubscription<List<Map<String, String>>>? _usersSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToNakama();
    });
  }
  
  @override
  void dispose() {
    _usersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _connectToNakama() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Show dialog to get username
      final username = await _showUsernameDialog();
      if (username == null || username.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _currentUsername = username;

      // Initialize and authenticate
      await _nakamaService.initialize();
      final authenticated = await _nakamaService.authenticate(username);

      if (!authenticated) {
        _showError('Failed to authenticate');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Join general channel to discover other users
      final joined = await _nakamaService.joinChannel('general');

      if (!joined) {
        _showError('Failed to join channel');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get initial users list
      _updateUsersList();
      
      // Listen to users stream for real-time updates
      _usersSubscription?.cancel();
      _usersSubscription = _nakamaService.usersStream.listen((users) {
        if (mounted) {
          setState(() {
            _users = users;
          });
        }
      });

      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('Connection error: $e');
      print('Stack trace: $stackTrace');
      _showError('Connection error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateUsersList() {
    setState(() {
      _users = _nakamaService.getUsers();
      // Filter out current user
      _users =
          _users.where((user) => user['id'] != _nakamaService.userId).toList();
    });
  }

  Future<String?> _showUsernameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter Username'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Your username',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _navigateToChat(String targetUserId, String targetUsername) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PrivateChatScreen(
          targetUserId: targetUserId,
          targetUsername: targetUsername,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isConnected ? 'Users - $_currentUsername' : 'Connecting...'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No other users online',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _updateUsersList,
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    _updateUsersList();
                  },
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            user['username']?.substring(0, 1).toUpperCase() ??
                                'U',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(user['username'] ?? 'Unknown'),
                        subtitle: Text('ID: ${user['id']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _navigateToChat(
                          user['id']!,
                          user['username'] ?? 'Unknown',
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
