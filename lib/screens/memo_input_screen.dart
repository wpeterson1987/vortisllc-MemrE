import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/memo_models.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'memo_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';
import 'package:MemrE/services/subscription_provider.dart'; // Adjust the path as needed

class MemoInputScreen extends StatefulWidget {
  final int userId;
  final Memo? memoToEdit;
  final dynamic sharedContent;
  final String? attachmentFileName;
  final AttachmentType? attachmentType;
  final bool fromSharedContent;

  const MemoInputScreen({
    Key? key,
    required this.userId,
    this.memoToEdit,
    this.sharedContent,
    this.attachmentFileName,
    this.attachmentType,
    this.fromSharedContent = false,
  }) : super(key: key);

  @override
  State<MemoInputScreen> createState() => _MemoInputScreenState();
}

class _MemoInputScreenState extends State<MemoInputScreen> {
  final DatabaseService _dbService = DatabaseService();
  late final NotificationService _notificationService;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();

  List<Reminder> selectedReminders = [];
  bool _isLoading = false;

  // Attachment related fields
  Uint8List? _attachmentData;
  String? _attachmentFileName;
  AttachmentType? _attachmentType;

  @override
  void initState() {
    super.initState();
    NotificationService.initialize();
    print('MemoInputScreen initialized');

    // Schedule this to run after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final provider =
              Provider.of<SubscriptionProvider>(context, listen: false);
          _notificationService =
              NotificationService(subscriptionProvider: provider);
          print('Initialized NotificationService with subscription provider');
        } catch (e) {
          print('Error initializing NotificationService: $e');
          _notificationService = NotificationService();
        }
      }
    });

    if (widget.memoToEdit != null) {
      print('\n========== LOADING MEMO FOR EDITING ==========');
      print('MemrE ID: ${widget.memoToEdit!.id}');
      print('Description: ${widget.memoToEdit!.description}');
      print('Number of reminders: ${widget.memoToEdit!.reminders.length}');
      for (var reminder in widget.memoToEdit!.reminders) {
        print('Reminder time: ${reminder.time}');
        print('Screen notification: ${reminder.useScreenNotification}');
        print('Email: ${reminder.emailAddress}');
        print('Phone: ${reminder.phoneNumber}');
      }
      print('===========================================\n');

      _descriptionController.text = widget.memoToEdit!.description;

      if (widget.memoToEdit!.attachmentData != null) {
        _attachmentData = widget.memoToEdit!.attachmentData;
        _attachmentFileName = widget.memoToEdit!.fileName;
        _attachmentType = widget.memoToEdit!.attachmentType;
      }

      print('Description loaded: ${_descriptionController.text}');
      print('===========================================\n');

      if (widget.memoToEdit!.textContent != null) {
        _memoController.text = widget.memoToEdit!.textContent!;
      }
    } else if (widget.sharedContent != null) {
      print('Processing shared content:');
      print('Content type: ${widget.sharedContent.runtimeType}');
      print('File name: ${widget.attachmentFileName}');
      print('Attachment type: ${widget.attachmentType}');

      if (widget.sharedContent is Uint8List) {
        _attachmentData = widget.sharedContent as Uint8List;
        _attachmentFileName = widget.attachmentFileName;
        _attachmentType = widget.attachmentType;
        print('Set attachment data: ${_attachmentData?.length} bytes');
      } else if (widget.sharedContent is String) {
        _memoController.text = widget.sharedContent.toString();
        print('Set text content: ${_memoController.text}');
      }
    }

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      setState(() {
        if (widget.memoToEdit != null) {
          print('Loading existing MemrE data:');

          selectedReminders = List<Reminder>.from(widget.memoToEdit!.reminders);
        }
      });
    } catch (e) {
      if (mounted) {
        print('Error loading initial data: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isValidFileType(String fileName) {
    final lowercaseName = fileName.toLowerCase();
    print('Checking file type for: $lowercaseName');

    if (lowercaseName.endsWith('.jpeg') ||
        lowercaseName.endsWith('.jpg') ||
        lowercaseName.endsWith('.png') ||
        lowercaseName.endsWith('.gif')) {
      _attachmentType = AttachmentType.image;
      return true;
    }

    if (lowercaseName.endsWith('.pdf') ||
        lowercaseName.endsWith('.doc') ||
        lowercaseName.endsWith('.docx')) {
      print('Valid document type detected');
      _attachmentType = AttachmentType.document;
      return true;
    }

    if (lowercaseName.endsWith('.mp4') || lowercaseName.endsWith('.mov')) {
      print('Valid video type detected');
      _attachmentType = AttachmentType.video;
      return true;
    }
    print('Invalid file type');
    return false;
  }

  Future<void> _pickFile() async {
    try {
      // Open file picker dialog
      final XTypeGroup typeGroup = XTypeGroup(
        label: 'All Files',
        extensions: [], // Empty list means all extensions
      );

      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

      if (file != null) {
        print('Selected file: ${file.name}');

        // Read the file data
        final Uint8List fileData = await file.readAsBytes();
        print('File size: ${fileData.length}');
        print('Has data: ${fileData.isNotEmpty}');

        if (fileData.isEmpty) {
          throw Exception('Could not read file data');
        }

        if (_isValidFileType(file.name)) {
          setState(() {
            _attachmentData = fileData;
            _attachmentFileName = file.name;
          });
          print('File loaded successfully');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid file type')),
            );
          }
        }
      } else {
        print('No file selected or file picking cancelled');
      }
    } catch (e) {
      print('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting file: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _attachmentData = bytes;
        _attachmentFileName = image.name;
        _attachmentType = AttachmentType.image;
      });
    }
  }

  Future<Map<String, dynamic>?> _showRepeatOptionsDialog({
    required DateTime initialDateTime,
    RepeatType initialRepeatType = RepeatType.none,
    DateTime? initialRepeatUntil,
  }) async {
    RepeatType selectedRepeatType = initialRepeatType;
    DateTime? selectedRepeatUntil = initialRepeatUntil;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Repeat Options'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<RepeatType>(
                    value: selectedRepeatType,
                    decoration: const InputDecoration(
                      labelText: 'Repeat',
                      border: OutlineInputBorder(),
                    ),
                    items: RepeatType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type == RepeatType.none
                            ? 'No Repeat'
                            : type.name.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (RepeatType? value) {
                      setState(() {
                        selectedRepeatType = value ?? RepeatType.none;
                        if (value == RepeatType.none) {
                          selectedRepeatUntil = null;
                        }
                      });
                    },
                  ),
                  if (selectedRepeatType != RepeatType.none) ...[
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final DateTime? endDate = await showDatePicker(
                          context: context,
                          initialDate: selectedRepeatUntil ??
                              initialDateTime.add(const Duration(days: 30)),
                          firstDate: initialDateTime,
                          lastDate: DateTime(2100),
                        );
                        if (endDate != null) {
                          setState(() {
                            selectedRepeatUntil = endDate;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Repeat Until (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          selectedRepeatUntil != null
                              ? DateFormat('MMM d, y')
                                  .format(selectedRepeatUntil!)
                              : 'Select End Date',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, {
                    'repeatType': selectedRepeatType,
                    'repeatUntil': selectedRepeatUntil,
                  }),
                  child: const Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showNotificationOptionsDialog({
    bool initialUseScreen = true,
    String? initialEmail,
    String? initialPhone,
    List<String>? initialEmails,
    List<String>? initialPhones,
  }) async {
    bool useScreen = initialUseScreen;
    final emailController = TextEditingController(text: initialEmail);
    final phoneController = TextEditingController(text: initialPhone);

    // For multiple recipients
    List<String> emailAddresses = initialEmails ?? [];
    if (initialEmail != null &&
        initialEmail.isNotEmpty &&
        !emailAddresses.contains(initialEmail)) {
      emailAddresses.add(initialEmail);
    }

    List<String> phoneNumbers = initialPhones ?? [];
    if (initialPhone != null &&
        initialPhone.isNotEmpty &&
        !phoneNumbers.contains(initialPhone)) {
      phoneNumbers.add(initialPhone);
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Notification Options',
                  style: TextStyle(fontSize: 18)),
              content: SizedBox(
                width: double.maxFinite, // Makes dialog wider
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Screen notification option
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.desktop_windows, size: 20),
                        title: Text('Screen Notification',
                            style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color)),
                        trailing: Switch(
                          value: useScreen,
                          onChanged: (value) {
                            setState(() => useScreen = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Email Notifications',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () {
                              if (emailController.text.isNotEmpty) {
                                final email = emailController.text.trim();
                                if (email.isNotEmpty &&
                                    !emailAddresses.contains(email)) {
                                  setState(() {
                                    emailAddresses.add(email);
                                    emailController.clear();
                                  });
                                }
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Email input field
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: emailController,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                  labelText: 'Email Address',
                                  labelStyle: TextStyle(fontSize: 14),
                                  prefixIcon: Icon(Icons.email, size: 20),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                ),
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 36, // Fixed width for button
                              child: IconButton(
                                icon: const Icon(Icons.contacts, size: 20),
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final email = await pickEmailContact();
                                  if (email != null && email.isNotEmpty) {
                                    setState(() {
                                      emailController.text = email;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Display selected email addresses
                      if (emailAddresses.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Selected Email Recipients (${emailAddresses.length}):',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              ...emailAddresses
                                  .map((email) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(email,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  emailAddresses.remove(email);
                                                });
                                              },
                                              child: const Icon(Icons.close,
                                                  size: 16, color: Colors.red),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Phone section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SMS Notifications',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () {
                              if (phoneController.text.isNotEmpty) {
                                final phone = phoneController.text.trim();
                                if (phone.isNotEmpty &&
                                    !phoneNumbers.contains(phone)) {
                                  setState(() {
                                    phoneNumbers.add(phone);
                                    phoneController.clear();
                                  });
                                }
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Phone input field
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: phoneController,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                  labelText: 'Phone Number',
                                  labelStyle: TextStyle(fontSize: 14),
                                  prefixIcon: Icon(Icons.phone, size: 20),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 36, // Fixed width for button
                              child: IconButton(
                                icon: const Icon(Icons.contacts, size: 20),
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final phone = await pickPhoneContact();
                                  if (phone != null && phone.isNotEmpty) {
                                    setState(() {
                                      phoneController.text = phone;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Display selected phone numbers
                      if (phoneNumbers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Selected SMS Recipients (${phoneNumbers.length}):',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              ...phoneNumbers
                                  .map((phone) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(phone,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  phoneNumbers.remove(phone);
                                                });
                                              },
                                              child: const Icon(Icons.close,
                                                  size: 16, color: Colors.red),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(fontSize: 14)),
                ),
                TextButton(
                  onPressed: () {
                    // Process phone numbers
                    List<String> formattedPhones = [];
                    for (String phone in phoneNumbers) {
                      String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
                      if (!cleanPhone.startsWith('1')) {
                        cleanPhone = '1$cleanPhone';
                      }

                      if (cleanPhone.length != 11) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Please enter valid 10-digit phone numbers'),
                          ),
                        );
                        return;
                      }

                      formattedPhones.add(cleanPhone);
                    }

                    // Add current phone if present and not already in the list
                    if (phoneController.text.isNotEmpty) {
                      String cleanPhone =
                          phoneController.text.replaceAll(RegExp(r'\D'), '');
                      if (!cleanPhone.startsWith('1')) {
                        cleanPhone = '1$cleanPhone';
                      }

                      if (cleanPhone.length != 11) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Please enter a valid 10-digit phone number'),
                          ),
                        );
                        return;
                      }

                      if (!formattedPhones.contains(cleanPhone)) {
                        formattedPhones.add(cleanPhone);
                      }
                    }

                    // Make sure at least one notification method is selected
                    if (!useScreen &&
                        emailAddresses.isEmpty &&
                        formattedPhones.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please select at least one notification method'),
                        ),
                      );
                      return;
                    }

                    // Add current email if present
                    if (emailController.text.isNotEmpty) {
                      String email = emailController.text.trim();
                      if (!emailAddresses.contains(email)) {
                        emailAddresses.add(email);
                      }
                    }

                    Navigator.pop(context, {
                      'useScreenNotification': useScreen,
                      'emailAddress': emailAddresses.isNotEmpty
                          ? emailAddresses.first
                          : null,
                      'phoneNumber': formattedPhones.isNotEmpty
                          ? formattedPhones.first
                          : null,
                      'emailAddresses': emailAddresses,
                      'phoneNumbers': formattedPhones,
                    });
                  },
                  child: const Text('Set', style: TextStyle(fontSize: 14)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> pickEmailContact() async {
    try {
      print('Starting email contact pick process');
      print('Requesting permission...');
      final hasPermission = await FlutterContacts.requestPermission();
      print('Permission request result: $hasPermission');

      if (hasPermission) {
        print('Permission granted, opening contact picker');
        final contact = await FlutterContacts.openExternalPick();

        if (contact != null) {
          print('Contact selected: ${contact.displayName}');
          final fullContact = await FlutterContacts.getContact(contact.id,
              withProperties: true);
          print('Loaded full contact data');

          if (fullContact != null && fullContact.emails.isNotEmpty) {
            final email = fullContact.emails.first.address;
            print('Found email: $email');
            return email;
          } else {
            print('No email found');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Selected contact has no email address')),
              );
            }
          }
        } else {
          print('No contact selected');
        }
      } else {
        print('Permission denied');
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Permission Required'),
                content: const Text(
                    'This app needs access to contacts to select email addresses. '
                    'Please grant contacts permission in your device settings.'),
                actions: [
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      print('Error in email contact picker: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing contacts: $e')),
        );
      }
    }
    return null;
  }

  Future<String?> pickPhoneContact() async {
    try {
      print('Starting phone contact pick process');
      print('Requesting permission...');
      final hasPermission = await FlutterContacts.requestPermission();
      print('Permission request result: $hasPermission');

      if (hasPermission) {
        print('Permission granted, opening contact picker');
        final contact = await FlutterContacts.openExternalPick();

        if (contact != null) {
          print('Contact selected: ${contact.displayName}');
          final fullContact = await FlutterContacts.getContact(contact.id,
              withProperties: true);
          print('Loaded full contact data');

          if (fullContact != null && fullContact.phones.isNotEmpty) {
            final phone = fullContact.phones.first.number;
            print('Found phone: $phone');
            return phone;
          } else {
            print('No phone found');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Selected contact has no phone number')),
              );
            }
          }
        } else {
          print('No contact selected');
        }
      } else {
        print('Permission denied');
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Permission Required'),
                content: const Text(
                    'This app needs access to contacts to select phone numbers. '
                    'Please grant contacts permission in your device settings.'),
                actions: [
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      print('Error in phone contact picker: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing contacts: $e')),
        );
      }
    }
    return null;
  }

  Future<void> _addReminder() async {
    print('\n=================== ADD REMINDER STARTED ===================');

    print('Current reminders count: ${selectedReminders.length}');

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    print('Selected date: $date');

    if (date != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      print('Selected time: $time');

      if (time != null && mounted) {
        final reminderDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );

        print('Combined reminder date/time: $reminderDateTime');

        // Show repeat options dialog
        final repeatSettings = await _showRepeatOptionsDialog(
          initialDateTime: reminderDateTime,
        );

        print('Repeat settings: $repeatSettings');

        if (mounted && repeatSettings != null) {
          // Show notification options after repeat settings
          final notificationOptions = await _showNotificationOptionsDialog();

          print('Notification options: $notificationOptions');

          if (mounted && notificationOptions != null) {
            print('Creating reminder with options:');
            print('DateTime: $reminderDateTime');
            print('RepeatType: ${repeatSettings['repeatType']}');
            print('RepeatUntil: ${repeatSettings['repeatUntil']}');
            print('UseScreen: ${notificationOptions['useScreenNotification']}');
            print('Email: ${notificationOptions['emailAddress']}');
            print('Phone: ${notificationOptions['phoneNumber']}');
            print('Email list: ${notificationOptions['emailAddresses']}');
            print('Phone list: ${notificationOptions['phoneNumbers']}');

            setState(() {
              selectedReminders.add(Reminder(
                time: reminderDateTime,
                repeatType: repeatSettings['repeatType'],
                repeatUntil: repeatSettings['repeatUntil'],
                timezoneOffset: DateTime.now().timeZoneOffset.inMinutes,
                useScreenNotification:
                    notificationOptions['useScreenNotification'],
                emailAddress: notificationOptions['emailAddress'],
                phoneNumber: notificationOptions['phoneNumber'],
                emailAddresses: notificationOptions['emailAddresses'],
                phoneNumbers: notificationOptions['phoneNumbers'],
              ));
            });

            // Add debug print before scheduling
            print('About to schedule notification...');

            await _notificationService.scheduleReminderNotification(
              memoId: widget.memoToEdit?.id ??
                  DateTime.now().millisecondsSinceEpoch,
              description: _descriptionController.text,
              memoContent: _memoController.text,
              reminderTime: reminderDateTime,
              useScreenNotification:
                  notificationOptions['useScreenNotification'],
              emailAddress: notificationOptions['emailAddress'],
              phoneNumber: notificationOptions['phoneNumber'],
              emailAddresses: notificationOptions['emailAddresses'],
              phoneNumbers: notificationOptions['phoneNumbers'],
            );

            print('Notification scheduled');
          }
        }
      }
    }

    print('========== ADD REMINDER PROCESS COMPLETED ==========\n');
  }

  void _deleteReminder(int index) {
    setState(() {
      selectedReminders.removeAt(index);
    });
  }

  Future<void> _editReminder(int index) async {
    final reminder = selectedReminders[index];

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: reminder.time,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(reminder.time),
      );

      if (time != null && mounted) {
        final reminderDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );

        final repeatSettings = await _showRepeatOptionsDialog(
          initialDateTime: reminderDateTime,
          initialRepeatType: reminder.repeatType,
          initialRepeatUntil: reminder.repeatUntil,
        );

        if (mounted && repeatSettings != null) {
          final notificationOptions = await _showNotificationOptionsDialog(
            initialUseScreen: reminder.useScreenNotification,
            initialEmail: reminder.emailAddress,
            initialPhone: reminder.phoneNumber,
            initialEmails: reminder.emailAddresses,
            initialPhones: reminder.phoneNumbers,
          );

          if (mounted && notificationOptions != null) {
            setState(() {
              selectedReminders[index] = Reminder(
                time: reminderDateTime,
                repeatType: repeatSettings['repeatType'],
                repeatUntil: repeatSettings['repeatUntil'],
                timezoneOffset: DateTime.now().timeZoneOffset.inMinutes,
                useScreenNotification:
                    notificationOptions['useScreenNotification'],
                emailAddress: notificationOptions['emailAddress'],
                phoneNumber: notificationOptions['phoneNumber'],
                emailAddresses: notificationOptions['emailAddresses'],
                phoneNumbers: notificationOptions['phoneNumbers'],
              );
            });
          }
        }
      }
    }
  }

  Widget _buildReminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Reminders',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _addReminder,
              icon: const Icon(Icons.add),
              label: const Text('Add/Edit Reminder'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (selectedReminders.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('No reminders set'),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: selectedReminders.length,
            itemBuilder: (context, index) =>
                _buildReminderItem(selectedReminders[index], index),
          ),
      ],
    );
  }

  Widget _buildReminderItem(Reminder reminder, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reminder.getDisplayText(),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _editReminder(index),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteReminder(index),
                ),
              ],
            ),
            if (reminder.repeatType != RepeatType.none)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  reminder.repeatUntil != null
                      ? 'Repeats ${reminder.repeatType.name} until ${DateFormat('MMM d, y').format(reminder.repeatUntil!)}'
                      : 'Repeats ${reminder.repeatType.name}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),

            // Notification methods - updated for multiple recipients
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  if (reminder.useScreenNotification)
                    _buildNotificationTag(Icons.desktop_windows, 'App'),
                  if (reminder.emailAddresses.isNotEmpty)
                    _buildNotificationTag(Icons.email,
                        'Emails (${reminder.emailAddresses.length})'),
                  if (reminder.phoneNumbers.isNotEmpty)
                    _buildNotificationTag(
                        Icons.phone, 'SMS (${reminder.phoneNumbers.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    if (_attachmentData == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getAttachmentTypeIcon()),
              const SizedBox(width: 8),
              Expanded(child: Text(_attachmentFileName ?? 'Attachment')),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _attachmentData = null;
                    _attachmentFileName = null;
                    _attachmentType = null;
                  });
                },
              ),
            ],
          ),
          if (_attachmentType == AttachmentType.image)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Image.memory(
                _attachmentData!,
                height: 200,
                fit: BoxFit.contain,
              ),
            ),
        ],
      ),
    );
  }

  IconData _getAttachmentTypeIcon() {
    switch (_attachmentType) {
      case AttachmentType.image:
        return Icons.image;
      case AttachmentType.document:
        return Icons.description;
      case AttachmentType.video:
        return Icons.video_library;
      default:
        return Icons.attach_file;
    }
  }

  Future<void> _saveMemo() async {
    print('\n========== STARTING SAVE MEMO PROCESS ==========');
    print('Is Edit Mode: ${widget.memoToEdit != null}');
    print('Number of reminders: ${selectedReminders.length}');

    if (_descriptionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final textContent =
          _memoController.text.isNotEmpty ? _memoController.text : null;

      // First, cancel any existing notifications
      await _notificationService.cancelAllNotifications();

      // Save to database
      late final int memoId;

      if (widget.memoToEdit != null) {
        print('Updating existing memo...');
        memoId = widget.memoToEdit!.id!;
        await _dbService.updateMemo(
          widget.userId,
          memoId,
          _descriptionController.text,
          textContent,
          _attachmentData,
          _attachmentFileName,
          _attachmentType,
          selectedReminders,
        );
        print('MemrE updated successfully');
      } else {
        try {
          memoId = await _dbService.createMemo(
            widget.userId,
            _descriptionController.text,
            textContent,
            _attachmentData,
            _attachmentFileName,
            _attachmentType,
            selectedReminders,
          );
        } catch (e) {
          print('Error creating memo: $e');
          throw Exception('Failed to create memo: $e');
        }
      }

      // Schedule notifications
      for (var reminder in selectedReminders) {
        print('Scheduling reminder for: ${reminder.time}');
        await _notificationService.scheduleReminderNotification(
          memoId: memoId,
          description: _descriptionController.text,
          memoContent: textContent ?? '',
          reminderTime: reminder.time,
          useScreenNotification: reminder.useScreenNotification,
          emailAddress: reminder.emailAddress,
          phoneNumber: reminder.phoneNumber,
          emailAddresses: reminder.emailAddresses,
          phoneNumbers: reminder.phoneNumbers,
          attachmentData: _attachmentData,
          attachmentFileName: _attachmentFileName,
          attachmentType: _attachmentType,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MemrE saved successfully')),
        );

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => MemoScreen(userId: widget.userId),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      print('Error saving memo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving memo: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    print('========== SAVE MEMO PROCESS COMPLETED ==========\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.memoToEdit != null ? 'Edit MemrE' : 'New MemrE'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // File Attachment Section
                  const Text('Add/Edit Attachment',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image),
                        label: const Text('Add Image'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Add File'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Attachment preview
                  _buildAttachmentPreview(),
                  const SizedBox(height: 16),

                  // Text content (always visible)
                  TextField(
                    controller: _memoController,
                    decoration: const InputDecoration(
                      labelText: 'MemrE Content',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),

                  const SizedBox(height: 16),

                  // Reminders section
                  _buildReminderSection(),

                  const SizedBox(height: 24),

                  // Save button
                  ElevatedButton(
                    onPressed: _saveMemo,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      widget.memoToEdit != null ? 'Update Memo' : 'Save Memo',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
