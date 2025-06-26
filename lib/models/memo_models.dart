import 'dart:typed_data';
import 'package:mysql1/mysql1.dart';
import 'package:intl/intl.dart';

enum AttachmentType { image, document, video }

extension AttachmentTypeExtension on AttachmentType {
  String get name {
    return toString().split('.').last;
  }

  static AttachmentType? fromString(String value) {
    return AttachmentType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => AttachmentType.document,
    );
  }
}

enum RepeatType { none, daily, weekly, monthly, yearly }

extension RepeatTypeExtension on RepeatType {
  String get name {
    return toString().split('.').last;
  }

  static RepeatType fromString(String? value) {
    if (value == null || value.isEmpty) return RepeatType.none;
    return RepeatType.values.firstWhere(
      (type) => type.name == value.toLowerCase(),
      orElse: () => RepeatType.none,
    );
  }
}

class Reminder {
  final int? id;
  final DateTime time;
  final RepeatType repeatType;
  final DateTime? repeatUntil;
  final int? timezoneOffset;
  final bool useScreenNotification;
  final String? emailAddress;
  final String? phoneNumber;
  final List<String> emailAddresses; // Field for multiple email addresses
  final List<String> phoneNumbers; // Field for multiple phone numbers

  Reminder({
    this.id,
    required this.time,
    this.repeatType = RepeatType.none,
    this.repeatUntil,
    required this.timezoneOffset,
    this.useScreenNotification = true,
    this.emailAddress,
    this.phoneNumber,
    List<String>? emailAddresses,
    List<String>? phoneNumbers,
  })  : emailAddresses =
            emailAddresses ?? (emailAddress != null ? [emailAddress] : []),
        phoneNumbers =
            phoneNumbers ?? (phoneNumber != null ? [phoneNumber] : []);

  Map<String, dynamic> toMap() {
    return {
      'time': time.millisecondsSinceEpoch,
      'repeatType': repeatType.index,
      'repeatUntil': repeatUntil?.millisecondsSinceEpoch,
      'timezoneOffset': timezoneOffset,
      'useScreenNotification': useScreenNotification ? 1 : 0,
      'emailAddress': emailAddress,
      'phoneNumber': phoneNumber,
      'emailAddresses': emailAddresses.join(','),
      'phoneNumbers': phoneNumbers.join(','),
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    List<String> parseList(String? value) {
      if (value == null || value.isEmpty) return [];
      return value.split(',').where((s) => s.isNotEmpty).toList();
    }

    return Reminder(
      time: DateTime.fromMillisecondsSinceEpoch(map['time']),
      repeatType: RepeatType.values[map['repeatType'] ?? 0],
      repeatUntil: map['repeatUntil'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['repeatUntil'])
          : null,
      timezoneOffset: map['timezoneOffset'] ?? 0,
      useScreenNotification: map['useScreenNotification'] == 1,
      emailAddress: map['emailAddress'],
      phoneNumber: map['phoneNumber'],
      emailAddresses: parseList(map['emailAddresses']),
      phoneNumbers: parseList(map['phoneNumbers']),
    );
  }

  String getDisplayText() {
    return DateFormat('MMM d, y - h:mm a').format(time);
  }

  String getRecipientsDisplayText() {
    List<String> displayParts = [];

    if (emailAddresses.isNotEmpty) {
      displayParts.add(
          '${emailAddresses.length} email${emailAddresses.length > 1 ? 's' : ''}');
    }

    if (phoneNumbers.isNotEmpty) {
      displayParts.add(
          '${phoneNumbers.length} SMS${phoneNumbers.length > 1 ? 's' : ''}');
    }

    if (useScreenNotification) {
      displayParts.add('app notification');
    }

    return displayParts.join(', ');
  }

  // Helper methods to add and remove recipients
  Reminder addPhoneNumber(String phoneNumber) {
    if (!phoneNumbers.contains(phoneNumber)) {
      final updatedPhoneNumbers = List<String>.from(phoneNumbers)
        ..add(phoneNumber);
      return Reminder(
        time: time,
        repeatType: repeatType,
        repeatUntil: repeatUntil,
        timezoneOffset: timezoneOffset,
        useScreenNotification: useScreenNotification,
        emailAddress: emailAddress,
        phoneNumber: this.phoneNumber,
        emailAddresses: emailAddresses,
        phoneNumbers: updatedPhoneNumbers,
      );
    }
    return this;
  }

  Reminder removePhoneNumber(String phoneNumber) {
    if (phoneNumbers.contains(phoneNumber)) {
      final updatedPhoneNumbers = List<String>.from(phoneNumbers)
        ..remove(phoneNumber);
      return Reminder(
        time: time,
        repeatType: repeatType,
        repeatUntil: repeatUntil,
        timezoneOffset: timezoneOffset,
        useScreenNotification: useScreenNotification,
        emailAddress: emailAddress,
        phoneNumber: this.phoneNumber,
        emailAddresses: emailAddresses,
        phoneNumbers: updatedPhoneNumbers,
      );
    }
    return this;
  }

  Reminder addEmailAddress(String email) {
    if (!emailAddresses.contains(email)) {
      final updatedEmailAddresses = List<String>.from(emailAddresses)
        ..add(email);
      return Reminder(
        time: time,
        repeatType: repeatType,
        repeatUntil: repeatUntil,
        timezoneOffset: timezoneOffset,
        useScreenNotification: useScreenNotification,
        emailAddress: emailAddress,
        phoneNumber: phoneNumber,
        emailAddresses: updatedEmailAddresses,
        phoneNumbers: phoneNumbers,
      );
    }
    return this;
  }

  Reminder removeEmailAddress(String email) {
    if (emailAddresses.contains(email)) {
      final updatedEmailAddresses = List<String>.from(emailAddresses)
        ..remove(email);
      return Reminder(
        time: time,
        repeatType: repeatType,
        repeatUntil: repeatUntil,
        timezoneOffset: timezoneOffset,
        useScreenNotification: useScreenNotification,
        emailAddress: emailAddress,
        phoneNumber: phoneNumber,
        emailAddresses: updatedEmailAddresses,
        phoneNumbers: phoneNumbers,
      );
    }
    return this;
  }
}

class Memo {
  final int? id;
  final String description;
  final String? textContent;
  final Uint8List? attachmentData;
  final String? fileName;
  final AttachmentType? attachmentType;
  final Map<String, dynamic>? metadata;
  final List<Reminder> reminders;

  Memo({
    this.id,
    required this.description,
    this.textContent,
    this.attachmentData,
    this.fileName,
    this.attachmentType,
    this.metadata,
    required this.reminders,
  });

  Map<String, dynamic> toMap() {
    return {
      'memo_id': id,
      'memo_desc': description,
      'memo': textContent,
      'file_name': fileName,
      'file_type': attachmentType?.name,
    };
  }

  factory Memo.fromMap(Map<String, dynamic> map) {
    return Memo(
      id: map['memo_id'],
      description: map['memo_desc'] ?? '',
      textContent: map['memo']?.toString(),
      attachmentData: map['file_data'],
      fileName: map['file_name'],
      attachmentType: map['file_type'] != null
          ? AttachmentTypeExtension.fromString(map['file_type'])
          : null,
      reminders: [], // These will be populated separately
    );
  }
}
