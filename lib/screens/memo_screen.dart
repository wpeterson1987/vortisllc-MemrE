import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/memo_models.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'memo_input_screen.dart';
import 'package:intl/intl.dart';
import '../services/shared_content_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:MemrE/services/subscription_provider.dart';
import 'package:MemrE/screens/widgets/subscription_info_widget.dart';

class MemoScreen extends StatefulWidget {
  final int userId;
  const MemoScreen({super.key, required this.userId});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> with WidgetsBindingObserver {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Memo> _memos = [];
  List<Memo> _filteredMemos = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print("MemoScreen initState called");
    _initializeScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // Handle app lifecycle changes to refresh subscription status
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground - refresh subscription status
      _refreshSubscriptionStatus();
    }
  }

  Future<void> _initializeScreen() async {
    if (!mounted) return;

    // Initialize subscription data
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);
    await subscriptionProvider.init();

    await _loadMemos();

    // Setup share handling
    if (mounted) {
      print("Setting up share handling...");
      SharedContentHandler.handleIncomingShares(context);
      print("Share handler initialized");
    }
  }

  Future<void> _refreshSubscriptionStatus() async {
    if (!mounted) return;

    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);
    await subscriptionProvider.forceRefresh();
  }

  Future<void> _loadMemos() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final memos = await _dbService.getMemos(widget.userId);
      if (!mounted) return;

      setState(() {
        _memos = memos;
        _filteredMemos = memos;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading MemrEs: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterMemos(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMemos = _memos;
      } else {
        _filteredMemos = _memos.where((memo) {
          final searchLower = query.toLowerCase();

          // Search in description
          final descriptionMatch =
              memo.description.toLowerCase().contains(searchLower);

          // Search in content if it's text
          bool contentMatch = false;
          if (memo.attachmentType == null && memo.textContent is String) {
            contentMatch =
                memo.textContent.toString().toLowerCase().contains(searchLower);
          }

          // Search in filename if it exists
          final fileNameMatch =
              memo.fileName?.toLowerCase().contains(searchLower) ?? false;

          return descriptionMatch || contentMatch || fileNameMatch;
        }).toList();
      }
    });
  }

  Future<void> _handleFileOpen(
      Uint8List fileData, String fileName, AttachmentType type) async {
    try {
      // Get the temporary directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';

      // Write the file
      final file = File(filePath);
      await file.writeAsBytes(fileData);

      // Open the file
      final result = await OpenFile.open(filePath);

      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      print('Error opening file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file: $e')),
      );
    }
  }

  Future<void> _deleteMemo(Memo memo) async {
    // Check subscription access before allowing delete
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);
    if (!subscriptionProvider.hasAppAccess) {
      _showSubscriptionRequiredDialog('delete memos');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete MemrE'),
        content: const Text('Are you sure you want to delete this MemrE?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _dbService.deleteMemo(widget.userId, memo.id!);
        await _loadMemos();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting MemrE: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _editMemo(Memo memo) async {
    // Check subscription access before allowing edit
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);
    if (!subscriptionProvider.hasAppAccess) {
      _showSubscriptionRequiredDialog('edit memos');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MemoInputScreen(
          userId: widget.userId,
          memoToEdit: memo,
        ),
      ),
    );
    if (result == true && mounted) {
      await _loadMemos();
    }
  }

  Future<void> _createNewMemo() async {
    // Check subscription access before allowing new memo creation
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);
    if (!subscriptionProvider.hasAppAccess) {
      _showSubscriptionRequiredDialog('create new memos');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MemoInputScreen(
          userId: widget.userId,
        ),
      ),
    );
    if (result == true && mounted) {
      _loadMemos();
    }
  }

  void _showSubscriptionRequiredDialog(String action) {
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(subscriptionProvider.trialExpired
              ? 'Trial Expired'
              : 'Upgrade Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                subscriptionProvider.trialExpired ? Icons.lock : Icons.star,
                size: 48,
                color: subscriptionProvider.trialExpired
                    ? Colors.red
                    : Colors.blue,
              ),
              SizedBox(height: 16),
              Text(
                subscriptionProvider.trialExpired
                    ? 'Your trial has expired. Upgrade to MemrE Premium to $action.'
                    : 'Upgrade to MemrE Premium to $action.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                '\$8.99/month',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/subscription');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('Upgrade Now'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMemoContent(Memo memo) {
    print('Displaying MemrE with ID: ${memo.id}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text content
        if (memo.textContent != null && memo.textContent!.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              memo.textContent!,
              style: const TextStyle(fontSize: 16),
            ),
          ),

        // Attachment if exists
        if (memo.attachmentType != null)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Attachment info header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(7)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getAttachmentIcon(memo.attachmentType!),
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          memo.fileName ?? 'Attachment',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Image preview
                if (memo.attachmentType == AttachmentType.image &&
                    memo.attachmentData != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(7),
                    ),
                    child: Image.memory(
                      memo.attachmentData!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),

                // Document preview
                if (memo.attachmentType == AttachmentType.document ||
                    memo.attachmentType == AttachmentType.video)
                  GestureDetector(
                    onTap: () {
                      if (memo.attachmentData != null) {
                        _handleFileOpen(
                          memo.attachmentData!,
                          memo.fileName ?? 'file${memo.id}',
                          memo.attachmentType!,
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            memo.attachmentType == AttachmentType.document
                                ? Icons.description
                                : Icons.video_library,
                            size: 32,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  memo.fileName ?? 'Attachment',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to open',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.download,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Video preview
                if (memo.attachmentType == AttachmentType.video)
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(7),
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        size: 48,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _getAttachmentIcon(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return Icons.image;
      case AttachmentType.document:
        return Icons.description;
      case AttachmentType.video:
        return Icons.video_library;
    }
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
      );
    }
  }

  Widget _buildReminderChip(Reminder reminder) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Chip(
        backgroundColor: Colors.green.withOpacity(0.1),
        label: SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      reminder.getDisplayText(),
                      style: const TextStyle(
                        color: Colors.green,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reminder.useScreenNotification)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(
                        Icons.desktop_windows,
                        size: 14,
                        color: Colors.green,
                      ),
                    ),
                  if (reminder.emailAddress != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(
                        Icons.email,
                        size: 14,
                        color: Colors.green,
                      ),
                    ),
                  if (reminder.phoneNumber != null)
                    const Icon(
                      Icons.phone,
                      size: 14,
                      color: Colors.green,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessRestrictedView() {
    return Consumer<SubscriptionProvider>(
      builder: (context, provider, child) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  provider.trialExpired ? Icons.lock : Icons.schedule,
                  size: 80,
                  color: provider.statusColor,
                ),
                SizedBox(height: 24),
                Text(
                  provider.trialExpired ? 'Trial Expired' : 'Limited Access',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: provider.statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                SizedBox(height: 16),
                Text(
                  provider.trialExpired
                      ? 'Your 14-day trial has expired. Upgrade to MemrE Premium to restore full access to your memos and features.'
                      : 'You have limited access during your trial period.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 32),
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'MemrE Premium',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '\$8.99/month',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      SizedBox(height: 16),
                      Column(
                        children: [
                          _buildFeatureItem('✓ Unlimited Memos'),
                          _buildFeatureItem('✓ Email & SMS Reminders'),
                          _buildFeatureItem('✓ Photo & File Attachments'),
                          _buildFeatureItem('✓ Cloud Backup'),
                          _buildFeatureItem('✓ Share & Export'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/subscription'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Upgrade to Premium',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                if (provider.trialExpired)
                  Text(
                    'Your data is safely stored and will be restored when you upgrade!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (context, subscriptionProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Your MemrE'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await _loadMemos();
                  await subscriptionProvider.forceRefresh();
                },
              ),
              // Show subscription status indicator
              Consumer<SubscriptionProvider>(
                builder: (context, provider, child) {
                  Color iconColor = provider.statusColor;
                  IconData icon = Icons.star;

                  if (provider.premiumActive) {
                    icon = Icons.check_circle;
                  } else if (provider.trialActive &&
                      provider.trialDaysRemaining <= 3) {
                    icon = Icons.warning;
                  } else if (!provider.hasAppAccess) {
                    icon = Icons.lock;
                  }

                  return Stack(
                    children: [
                      IconButton(
                        icon: Icon(icon, color: iconColor),
                        tooltip: 'Subscription: ${provider.statusMessage}',
                        onPressed: () =>
                            Navigator.pushNamed(context, '/subscription'),
                      ),
                      if (provider.trialActive &&
                          provider.trialDaysRemaining <= 3)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '${provider.trialDaysRemaining}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _handleLogout,
              ),
            ],
          ),
          body: Column(
            children: [
              // Show subscription info widget
              const SubscriptionInfoWidget(compact: true),

              // Check if user has app access
              if (!subscriptionProvider.hasAppAccess)
                Expanded(child: _buildAccessRestrictedView())
              else ...[
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search MemrEs...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _filterMemos('');
                              },
                            )
                          : null,
                    ),
                    onChanged: _filterMemos,
                  ),
                ),

                // Memo list
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _filteredMemos.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.note_add,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No MemrEs found',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Tap the + button to create your first MemrE',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filteredMemos.length,
                              itemBuilder: (context, index) {
                                final memo = _filteredMemos[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        title: Text(
                                          memo.description,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        trailing: PopupMenuButton(
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete,
                                                      size: 20,
                                                      color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Delete',
                                                      style: TextStyle(
                                                          color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                          onSelected: (value) async {
                                            if (value == 'edit') {
                                              print(
                                                  'Editing MemrE with ID: ${memo.id}');
                                              print(
                                                  'MemrE has ${memo.reminders.length} reminders');
                                              if (memo.reminders.isNotEmpty) {
                                                print(
                                                    'First reminder: ${memo.reminders.first.getDisplayText()}');
                                              }
                                              await _editMemo(memo);
                                            } else if (value == 'delete') {
                                              await _deleteMemo(memo);
                                            }
                                          },
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: _buildMemoContent(memo),
                                      ),
                                      if (memo.reminders.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (memo.reminders.isNotEmpty)
                                                Wrap(
                                                  spacing: 4,
                                                  children: memo.reminders
                                                      .map((reminder) =>
                                                          _buildReminderChip(
                                                              reminder))
                                                      .toList(),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ],
          ),
          floatingActionButton: subscriptionProvider.hasAppAccess
              ? FloatingActionButton(
                  onPressed: _createNewMemo,
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}
