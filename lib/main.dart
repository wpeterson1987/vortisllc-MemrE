import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/email_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'screens/memo_screen.dart';
import 'services/auth_service.dart';
import 'package:provider/provider.dart';
import 'services/subscription_provider.dart';
import 'screens/subscription_screen.dart';
import 'services/simple_notification_manager.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/platform_sms_service.dart';
import 'models/memo_models.dart';
import 'services/attachment_storage_service.dart';

// Define this top-level method for handling notification actions - WITH CRASH PROTECTION
@pragma('vm:entry-point')
Future<void> onNotificationActionReceived(ReceivedAction receivedAction) async {
  try {
    print('=== NOTIFICATION TAP DETECTED ===');
    print('Channel Key: ${receivedAction.channelKey}');
    print('Payload: ${receivedAction.payload}');

    // Handle notification tap for BOTH email and SMS
    if (receivedAction.channelKey == 'scheduled_channel') {
      final payload = receivedAction.payload;
      if (payload != null) {
        print('Processing notification immediately...');

        // Process the notification data immediately
        await _processNotificationImmediately(payload);
      } else {
        print('ERROR: Payload is null!');
      }
    }
  } catch (e) {
    print('❌ CRITICAL ERROR in notification handler: $e');
    print('Stack trace: ${StackTrace.current}');

    // Don't let the error crash the app - log it and continue
    try {
      // Attempt basic notification without attachments as fallback
      print('Attempting fallback notification processing...');
      if (receivedAction.payload != null) {
        await _processNotificationSafely(receivedAction.payload!);
      }
    } catch (fallbackError) {
      print('❌ Fallback also failed: $fallbackError');
    }
  }
}

// Fallback notification processing without attachments
Future<void> _processNotificationSafely(Map<String, String?> payload) async {
  try {
    print('=== SAFE NOTIFICATION PROCESSING ===');

    final description = payload['description'] ?? 'Reminder';
    final memoContent = payload['memoContent'] ?? '';
    final hasEmails = payload['hasEmails'] == 'true';
    final hasSMS = payload['hasSMS'] == 'true';

    print('Safe mode - Description: $description');
    print('Safe mode - Has emails: $hasEmails');
    print('Safe mode - Has SMS: $hasSMS');

    // Process emails WITHOUT attachments in safe mode
    if (hasEmails) {
      try {
        final emailsJson = payload['emailAddresses'] ?? '[]';
        final List<dynamic> emailsList = jsonDecode(emailsJson);
        print('Safe mode - Processing ${emailsList.length} emails');

        final emailService = EmailService();

        for (final email in emailsList) {
          print('Safe mode - Opening email for: $email');
          await emailService.sendEmail(
            to: email.toString(),
            subject: 'MemrE Reminder: $description',
            body: 'Reminder for your MemrE:\n\n$description\n\n$memoContent',
            // No attachments in safe mode
          );
          await Future.delayed(Duration(seconds: 2));
        }
      } catch (e) {
        print('Safe mode email error: $e');
      }
    }

    // Process SMS in safe mode
    if (hasSMS) {
      try {
        final phoneNumbersJson = payload['phoneNumbers'] ?? '[]';
        final List<dynamic> phoneNumbersList = jsonDecode(phoneNumbersJson);
        final List<String> phoneNumbers =
            phoneNumbersList.map((phone) => phone.toString()).toList();

        if (phoneNumbers.isNotEmpty) {
          print('Safe mode - Processing ${phoneNumbers.length} SMS');
          final message = 'Reminder: $description\n$memoContent';

          await PlatformSMSService.sendBulkSMSWithQueue(
            recipients: phoneNumbers,
            message: message,
          );
        }
      } catch (e) {
        print('Safe mode SMS error: $e');
      }
    }

    print('=== SAFE NOTIFICATION PROCESSING COMPLETE ===');
  } catch (e) {
    print('❌ Even safe processing failed: $e');
  }
}

// Process notifications immediately when tapped - WITH IMPROVED ORDERING
Future<void> _processNotificationImmediately(
    Map<String, String?> payload) async {
  try {
    print('=== PROCESSING NOTIFICATION IMMEDIATELY ===');

    final description = payload['description'] ?? 'Reminder';
    final memoContent = payload['memoContent'] ?? '';
    final hasEmails = payload['hasEmails'] == 'true';
    final hasSMS = payload['hasSMS'] == 'true';
    bool hasValidAttachment = payload['hasAttachment'] == 'true';

    print('Description: $description');
    print('Memo content: $memoContent');
    print('Has emails: $hasEmails');
    print('Has SMS: $hasSMS');
    print('Has attachment: $hasValidAttachment');

    // Load attachment data from file if present
    Uint8List? attachmentData;
    String? attachmentFileName;
    AttachmentType? attachmentType;

    if (hasValidAttachment) {
      try {
        final attachmentFilePath = payload['attachmentFilePath'];
        attachmentFileName = payload['attachmentFileName'];
        final attachmentTypeString = payload['attachmentType'];

        print('Attachment file path: $attachmentFilePath');
        print('Attachment filename: $attachmentFileName');
        print('Attachment type string: $attachmentTypeString');

        if (attachmentFilePath != null && attachmentFileName != null) {
          // Load attachment data from stored file
          attachmentData =
              await AttachmentStorageService.loadAttachmentFromPath(
                  attachmentFilePath);

          if (attachmentData != null) {
            // Parse attachment type
            if (attachmentTypeString != null) {
              switch (attachmentTypeString) {
                case 'AttachmentType.image':
                  attachmentType = AttachmentType.image;
                  break;
                case 'AttachmentType.video':
                  attachmentType = AttachmentType.video;
                  break;
                case 'AttachmentType.document':
                  attachmentType = AttachmentType.document;
                  break;
                default:
                  attachmentType =
                      AttachmentStorageService.getAttachmentTypeFromPath(
                          attachmentFilePath);
              }
            } else {
              // Determine type from file path
              attachmentType =
                  AttachmentStorageService.getAttachmentTypeFromPath(
                      attachmentFilePath);
            }

            print(
                '✅ Attachment loaded: $attachmentFileName (${attachmentData.length} bytes)');
            print('✅ Attachment type: $attachmentType');
          } else {
            print('❌ Failed to load attachment data');
            hasValidAttachment = false;
          }
        } else {
          print('❌ Missing attachment file path or filename');
          hasValidAttachment = false;
        }
      } catch (e) {
        print('❌ Error loading attachment: $e');
        print('Stack trace: ${StackTrace.current}');
        hasValidAttachment = false;
      }
    }

    // Small delay to ensure everything is ready
    await Future.delayed(Duration(milliseconds: 500));

    // IMPROVED: Better handling for mixed notifications with more debugging
    if (hasEmails && hasSMS) {
      print('=== BOTH EMAIL AND SMS DETECTED - USING SMART PROCESSING ===');
      
      // Get email data from payload
      final emailsJson = payload['emailAddresses'] ?? '[]';
      print('📧 Email addresses JSON: $emailsJson');
      
      // Store email data for later processing (after all SMS are sent)
      final emailDataToStore = {
        'emailAddresses': emailsJson,
        'description': description,
        'memoContent': memoContent,
        'hasValidAttachment': hasValidAttachment,
        'attachmentFilePath': payload['attachmentFilePath'],
        'attachmentFileName': payload['attachmentFileName'],
        'attachmentType': payload['attachmentType'],
      };
      
      print('📧 Storing email data: $emailDataToStore');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_emails_after_sms', jsonEncode(emailDataToStore));
      
      // Verify the data was stored
      final storedData = prefs.getString('pending_emails_after_sms');
      print('📧 Verified stored email data: $storedData');
      
      print('📧 Email data stored for processing after SMS queue completes');
      
      // Process SMS first and ONLY SMS
      await _processSMSNotifications(payload, description, memoContent);
      
      // Don't process emails immediately - they'll be processed when SMS queue is complete
      
    } else if (hasEmails) {
      // Only emails
      await _processEmailNotifications(
        payload, 
        description, 
        memoContent, 
        attachmentData, 
        attachmentFileName, 
        attachmentType,
        hasValidAttachment
      );
      
    } else if (hasSMS) {
      // Only SMS
      await _processSMSNotifications(payload, description, memoContent);
    }

    print('=== NOTIFICATION PROCESSING COMPLETE ===');
  } catch (e) {
    print('✗ Error processing notification immediately: $e');
    print('Stack trace: ${StackTrace.current}');
  }
}

// Separate SMS processing function
Future<void> _processSMSNotifications(
    Map<String, String?> payload, 
    String description, 
    String memoContent) async {
  try {
    final phoneNumbersJson = payload['phoneNumbers'] ?? '[]';
    final List<dynamic> phoneNumbersList = jsonDecode(phoneNumbersJson);
    final List<String> phoneNumbers =
        phoneNumbersList.map((phone) => phone.toString()).toList();

    print('✓ Processing ${phoneNumbers.length} SMS notifications');

    if (phoneNumbers.isNotEmpty) {
      final message = 'Reminder: $description\n$memoContent';
      
      if (phoneNumbers.length == 1) {
        // Single SMS - send immediately
        print('📱 Sending single SMS to: ${phoneNumbers[0]}');
        
        final success = await PlatformSMSService.sendSMS(
          to: phoneNumbers[0],
          message: message,
        );
        
        if (success) {
          print('✅ SMS opened successfully for: ${phoneNumbers[0]}');
        } else {
          print('❌ Failed to open SMS for: ${phoneNumbers[0]}');
        }
        
      } else {
        // Multiple SMS - use improved queue approach
        print('📱 Processing ${phoneNumbers.length} SMS with smart queue...');
        
        final results = await PlatformSMSService.sendBulkSMSWithSmartQueue(
          recipients: phoneNumbers,
          message: message,
        );

        print('SMS processing results: $results');

        // Log individual results
        final successCount = results.values.where((success) => success).length;
        print('✅ SMS Summary: $successCount/${results.length} opened successfully');
      }
    }

    print('✓ SMS processing complete');
  } catch (smsProcessingError) {
    print('❌ Error processing SMS: $smsProcessingError');
  }
}

// Separate email processing function
Future<void> _processEmailNotifications(
    Map<String, String?> payload,
    String description,
    String memoContent,
    Uint8List? attachmentData,
    String? attachmentFileName,
    AttachmentType? attachmentType,
    bool hasValidAttachment) async {
  try {
    final emailsJson = payload['emailAddresses'] ?? '[]';
    print('Emails JSON: $emailsJson');

    final List<dynamic> emailsList = jsonDecode(emailsJson);
    print('✓ Processing ${emailsList.length} email notifications');

    if (emailsList.isNotEmpty) {
      final emailService = EmailService();
      final List<String> emailAddresses = emailsList.map((email) => email.toString()).toList();
      
      print('📧 Attempting to send email to ${emailAddresses.length} recipients');
      
      // Try sending to all recipients at once
      try {
        final success = await emailService.sendEmailToMultipleRecipients(
          recipients: emailAddresses,
          subject: 'MemrE Reminder: $description',
          body: 'Reminder for your MemrE:\n\n$description\n\n$memoContent',
          attachmentData: attachmentData,
          attachmentFileName: attachmentFileName,
          attachmentType: attachmentType,
        );
        
        if (success) {
          print('✅ Email client opened with ${emailAddresses.length} recipients');
        } else {
          throw Exception('Multiple recipient email failed');
        }
        
      } catch (multipleEmailError) {
        print('❌ Multiple recipient email error: $multipleEmailError');
        print('🔄 Falling back to sequential email approach...');
        
        final results = await emailService.sendEmailToRecipientsSequentially(
          recipients: emailAddresses,
          subject: 'MemrE Reminder: $description',
          body: 'Reminder for your MemrE:\n\n$description\n\n$memoContent',
          attachmentData: attachmentData,
          attachmentFileName: attachmentFileName,
          attachmentType: attachmentType,
        );
        
        print('Sequential email results: $results');
      }
    }

    print('✓ Email processing complete');
  } catch (emailProcessingError) {
    print('❌ Error processing emails: $emailProcessingError');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.initialize();
  await SimpleNotificationManager.initialize();

  // Set up global notification action listeners
  AwesomeNotifications().setListeners(
    onActionReceivedMethod: onNotificationActionReceived,
    onNotificationCreatedMethod: _onNotificationCreated,
    onNotificationDisplayedMethod: _onNotificationDisplayed,
    onDismissActionReceivedMethod: _onDismissActionReceived,
  );

  final authService = AuthService();
  final userId = await authService.getLoggedInUserId();

  // Run the app with providers
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ],
      child: MyApp(initialUserId: userId),
    ),
  );
}

// Define these top-level notification handler methods
@pragma('vm:entry-point')
Future<void> _onNotificationCreated(
    ReceivedNotification receivedNotification) async {
  print('Notification created: ${receivedNotification.id}');
}

@pragma('vm:entry-point')
Future<void> _onNotificationDisplayed(
    ReceivedNotification receivedNotification) async {
  print('Notification displayed: ${receivedNotification.id}');
}

@pragma('vm:entry-point')
Future<void> _onDismissActionReceived(ReceivedAction receivedAction) async {
  print('Notification dismissed: ${receivedAction.id}');
}

class MyApp extends StatefulWidget {
  final int? initialUserId;

  const MyApp({super.key, this.initialUserId});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Request notification permissions
    AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });

    // Check for any pending SMS when app starts (backup mechanism)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForPendingSMS();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  
  print('=== APP LIFECYCLE CHANGE: $state ===');

  // When app becomes active, check for pending SMS
  if (state == AppLifecycleState.resumed) {
    print('App resumed - checking for pending SMS with delay...');
    
    // Add multiple checks with different delays to ensure we catch the resume
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        print('First SMS queue check (500ms delay)');
        _checkAndProcessSMSQueue();
      }
    });
    
    Future.delayed(Duration(milliseconds: 1500), () {
      if (mounted) {
        print('Second SMS queue check (1.5s delay)');
        _checkAndProcessSMSQueue();
      }
    });
    
    Future.delayed(Duration(milliseconds: 3000), () {
      if (mounted) {
        print('Third SMS queue check (3s delay)');
        _checkAndProcessSMSQueue();
      }
    });
    
    // ADD THIS: Manual email check as backup
    Future.delayed(Duration(milliseconds: 4000), () {
      if (mounted) {
        print('Manual email check (4s delay)');
        _manuallyCheckForPendingEmails();
      }
    });
  }
}

  Future<void> _manuallyCheckForPendingEmails() async {
  try {
    print('=== MANUAL CHECK FOR PENDING EMAILS ===');
    final prefs = await SharedPreferences.getInstance();
    final pendingEmailsJson = prefs.getString('pending_emails_after_sms');
    
    if (pendingEmailsJson != null) {
      print('📧 Found pending emails manually, processing...');
      await PlatformSMSService.resumePendingSMS(); // This will check emails too
    } else {
      print('📧 No pending emails found in manual check');
    }
  } catch (e) {
    print('❌ Error in manual email check: $e');
  }
}



  Future<void> _checkAndProcessSMSQueue() async {
    try {
      print('=== CHECKING SMS QUEUE ON RESUME ===');
      
      // Check smart queue first
      final smartQueueStatus = await PlatformSMSService.getSmartSMSQueueStatus();
      print('Smart queue status: $smartQueueStatus');
      
      if (smartQueueStatus['isActive'] == true) {
        final recipients = smartQueueStatus['recipients'] as List<dynamic>;
        final currentIndex = smartQueueStatus['currentIndex'] as int;
        
        if (recipients.isNotEmpty && currentIndex < recipients.length) {
          print('🚀 Processing queued SMS: ${currentIndex + 1} of ${recipients.length}');
          print('Next recipient: ${recipients[currentIndex]}');
          
          final success = await PlatformSMSService.processNextQueuedSMS();
          if (success) {
            print('✅ Queued SMS processed successfully');
          } else {
            print('❌ Failed to process queued SMS');
          }
        } else {
          print('Smart queue is active but no more SMS to process');
        }
      } else {
        print('No active smart SMS queue found');
        
        // Check original queue as fallback
        final originalQueueStatus = await PlatformSMSService.getSMSQueueStatus();
        if (originalQueueStatus['isActive'] == true) {
          print('Found original SMS queue, processing...');
          await PlatformSMSService.resumePendingSMS();
        }
      }
      
      // Also check for any pending SMS backup
      await _checkForPendingSMS();
      
    } catch (e) {
      print('❌ Error checking SMS queue: $e');
    }
  }

  Future<void> _checkForPendingSMS() async {
    try {
      print('=== CHECKING FOR PENDING SMS (BACKUP) ===');
      final prefs = await SharedPreferences.getInstance();
      final pendingSMSJson = prefs.getString('pending_sms_only');

      if (pendingSMSJson != null && mounted) {
        print('✓ Found pending SMS data (using backup mechanism)');

        // Clear the stored SMS
        await prefs.remove('pending_sms_only');

        // Parse the payload
        final smsData = Map<String, dynamic>.from(jsonDecode(pendingSMSJson));
        final List<String> phoneNumbers =
            List<String>.from(smsData['phoneNumbers']);
        final String description = smsData['description'];
        final String memoContent = smsData['memoContent'];

        print('Processing SMS for ${phoneNumbers.length} recipients (backup)');

        // Small delay to ensure UI is ready
        await Future.delayed(Duration(milliseconds: 500));

        final message = 'Reminder: $description\n$memoContent';

        // Use platform SMS service directly
        final results = await PlatformSMSService.sendBulkSMS(
          recipients: phoneNumbers,
          message: message,
        );

        print('Backup SMS processing results: $results');
      } else {
        print('No pending SMS found (backup check)');
      }
    } catch (e) {
      print('✗ Error checking for pending SMS: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize the subscription provider if user is logged in
    if (widget.initialUserId != null) {
      // We access the provider here to initialize it, but we don't need the result
      Future.microtask(() =>
          Provider.of<SubscriptionProvider>(context, listen: false).init());
    }

    return MaterialApp(
      title: 'MemrE',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: widget.initialUserId != null
          ? MemoScreen(userId: widget.initialUserId!)
          : const LoginScreen(),
      routes: {
        '/home': (context) => widget.initialUserId != null
            ? MemoScreen(userId: widget.initialUserId!)
            : const LoginScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
      },
    );
  }}

// Wrapper for LoginScreen to handle notification permissions
class NotificationAwareLoginScreen extends StatefulWidget {
  const NotificationAwareLoginScreen({Key? key}) : super(key: key);

  @override
  State<NotificationAwareLoginScreen> createState() =>
      _NotificationAwareLoginScreenState();
}

class _NotificationAwareLoginScreenState
    extends State<NotificationAwareLoginScreen> {
  @override
  void initState() {
    super.initState();
    _setupNotificationListeners();
  }

  void _setupNotificationListeners() {
    // Request notification permissions if not already granted
    AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const LoginScreen();
  }
}