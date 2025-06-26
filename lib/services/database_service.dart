import 'package:mysql1/mysql1.dart';
import '../models/memo_models.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math'; // For the min() function in debug logging

class DatabaseService {
  Future<MySqlConnection> _getConnection() async {
    final settings = ConnectionSettings(
      host: 'memre.vortisllc.com',
      port: 3306,
      user: 'vortis5_vortismemre',
      password: r'Wd$)!rU.v2pE',
      db: 'vortis5_memredata',
    );

    return await MySqlConnection.connect(settings);
  }

  Future<List<Memo>> getDueReminders(int userId) async {
    final conn = await _getConnection();
    try {
      // Get the current time in UTC
      final now = DateTime.now().toUtc().toString();

      // Query reminders that are due
      final results = await conn.query('''
      SELECT 
        m.memo_id,
        m.memo_desc,
        m.memo,
        r.reminder_id,
        r.reminder_time,
        r.repeat_type,
        r.repeat_until,
        r.use_screen_notification,
        r.email_address,
        r.phone_number,
        r.email_addresses,
        r.phone_numbers
      FROM user_${userId}_reminder r
      JOIN user_${userId}_memo_reminder mr ON r.reminder_id = mr.reminder_id
      JOIN user_${userId}_memo m ON mr.memo_id = m.memo_id
      WHERE r.reminder_time <= ?
      AND (r.processed IS NULL OR r.processed = 0)
    ''', [now]);

      // Process results into MemrE objects with their reminders
      // This implementation will depend on your data structure

      // Remember to mark reminders as processed or handle repeating reminders

      return []; // Replace with your actual implementation
    } catch (e) {
      print('Error getting due reminders: $e');
      return [];
    } finally {
      await conn.close();
    }
  }

  Future<void> sendEmailReminders(
      Reminder reminder, String memoDesc, String memoContent) async {
    // Your implementation...
  }

  //Future<void> sendSmsReminders(Reminder reminder, String memoDesc) async {
  // Your implementation...
  //}

  Future<bool> testConnection() async {
    try {
      final conn = await _getConnection();
      await conn.query('SELECT 1');
      await conn.close();
      print('Database connection successful');
      return true;
    } catch (e) {
      print('Database connection failed: $e');
      return false;
    }
  }

  // Helper methods for converting between string lists and database strings
  String _stringListToDbString(List<String>? list) {
    if (list == null || list.isEmpty) return '';
    return list.join(
      '|',
    ); // Using pipe to separate multiple recipients since comma is used elsewhere
  }

  List<String> _dbStringToStringList(String? dbString) {
    if (dbString == null || dbString.isEmpty) return [];
    return dbString.split('|').where((s) => s.isNotEmpty).toList();
  }

  // Modify the database schema to add new columns
  Future<void> updateSchema(int userId) async {
    final conn = await _getConnection();
    try {
      print('Checking and updating schema for user $userId');

      // Check if columns exist first
      final columnsResult = await conn.query(
        "SHOW COLUMNS FROM user_${userId}_reminder LIKE 'email_addresses'",
      );

      if (columnsResult.isEmpty) {
        print('Adding multiple recipients columns for user $userId');

        // Add columns for multiple recipients
        await conn.query(
          'ALTER TABLE user_${userId}_reminder ADD COLUMN email_addresses TEXT',
        );

        await conn.query(
          'ALTER TABLE user_${userId}_reminder ADD COLUMN phone_numbers TEXT',
        );

        // Migrate existing data
        print('Migrating existing data to new columns');
        final existingReminders = await conn.query(
          'SELECT reminder_id, email_address, phone_number FROM user_${userId}_reminder',
        );

        for (var row in existingReminders) {
          final reminderId = row[0];
          final emailAddress = row[1] as String?;
          final phoneNumber = row[2] as String?;

          if (emailAddress != null && emailAddress.isNotEmpty) {
            await conn.query(
              'UPDATE user_${userId}_reminder SET email_addresses = ? WHERE reminder_id = ?',
              [emailAddress, reminderId],
            );
          }

          if (phoneNumber != null && phoneNumber.isNotEmpty) {
            await conn.query(
              'UPDATE user_${userId}_reminder SET phone_numbers = ? WHERE reminder_id = ?',
              [phoneNumber, reminderId],
            );
          }
        }

        print('Schema update completed for user $userId');
      } else {
        print('Multiple recipients columns already exist for user $userId');
      }
    } catch (e) {
      print('Error updating schema: $e');
    } finally {
      await conn.close();
    }
  }

  Future<List<Memo>> getMemos(int userId) async {
    final conn = await _getConnection();
    try {
      print('Fetching MemrEs for user $userId');

      // Ensure schema is updated
      await updateSchema(userId);

      final results = await conn.query('''
        SELECT 
          m.memo_id,
          m.memo_desc,
          m.memo,
          a.file_type,
          a.file_name,
          a.file_data,
          GROUP_CONCAT(DISTINCT CONCAT(
            r.reminder_time, ':::',
            COALESCE(r.repeat_type, ''), ':::',
            COALESCE(r.repeat_until, ''), ':::',
            COALESCE(r.timezone_offset, '0'), ':::',
            COALESCE(r.use_screen_notification, 1), ':::',
            COALESCE(r.email_address, ''), ':::',
            COALESCE(r.phone_number, ''), ':::',
            COALESCE(r.email_addresses, ''), ':::',
            COALESCE(r.phone_numbers, '')
          )) as reminders
        FROM user_${userId}_memo m
        LEFT JOIN user_${userId}_attachment a ON m.memo_id = a.memo_id
        LEFT JOIN user_${userId}_memo_reminder mr ON m.memo_id = mr.memo_id
        LEFT JOIN user_${userId}_reminder r ON mr.reminder_id = r.reminder_id
        GROUP BY m.memo_id
        ORDER BY m.memo_id DESC
      ''');

      print('Found ${results.length} MemrEs');

      return results.map((row) {
        print('Processing memo ID: ${row['memo_id']}');
        print('Reminders raw data: ${row['reminders']}');

        // Handle text content
        String? textContent;
        if (row['memo'] != null) {
          textContent = row['memo'].toString();
          print('Found text content length: ${textContent.length}');
        }

        // Handle attachment data
        Uint8List? attachmentData;
        if (row['file_data'] != null) {
          final fileData = row['file_data'];
          print('File data type: ${fileData.runtimeType}');

          if (fileData is Uint8List) {
            print('File data is already Uint8List');
            attachmentData = fileData;
            print('Attachment data length: ${attachmentData.length}');
          } else if (fileData is List<int>) {
            print('Converting List<int> to Uint8List');
            attachmentData = Uint8List.fromList(fileData);
            print('Converted data length: ${attachmentData.length}');
          } else {
            try {
              print('Attempting to convert to bytes');
              var tempData = fileData.toBytes();
              if (tempData != null) {
                attachmentData = tempData;
                //  print(
                //      'Successfully converted to bytes, length: ${attachmentData.length}');
              } else {
                print('Conversion resulted in null data');
              }
            } catch (e) {
              print('Error converting file data: $e');
            }
          }

          print('File type: ${row['file_type']}');
          print('File name: ${row['file_name']}');
        } else {
          print('No file data found for this memo');
        }

        final memo = Memo(
          id: row['memo_id'],
          description: row['memo_desc'] ?? '',
          textContent: row['memo']?.toString(),
          attachmentData: row['file_data'] != null
              ? Uint8List.fromList(
                  (row['file_data'] as Blob).toBytes(),
                ) // Convert to Uint8List
              : null,
          fileName: row['file_name'],
          attachmentType: row['file_type'] != null
              ? AttachmentTypeExtension.fromString(row['file_type'])
              : null,
          reminders: _parseReminders(row['reminders']?.toString() ?? ''),
        );
        print('Parsed reminders count: ${memo.reminders.length}');
        if (memo.reminders.isNotEmpty) {
          print('First reminder: ${memo.reminders.first.getDisplayText()}');
        }
        return memo;
      }).toList();
    } catch (e, stackTrace) {
      print('Error in getMemos: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    } finally {
      await conn.close();
    }
  }

  List<Reminder> _parseReminders(String remindersStr) {
    print('Parsing reminders string: $remindersStr');
    if (remindersStr.isEmpty) return [];

    try {
      return remindersStr
          .split(',')
          .map((str) {
            final parts = str.trim().split(':::');
            print('Split parts: $parts');

            if (parts.isNotEmpty) {
              DateTime? reminderTime;
              try {
                reminderTime = DateTime.parse(parts[0].trim());
              } catch (e) {
                print('Error parsing date: $e');
                return null;
              }

              String repeatTypeStr = parts.length > 1 ? parts[1].trim() : '';
              String repeatUntilStr = parts.length > 2 ? parts[2].trim() : '';
              int timezoneOffset =
                  parts.length > 3 ? int.tryParse(parts[3].trim()) ?? 0 : 0;
              bool useScreenNotification =
                  parts.length > 4 ? parts[4].trim() == '1' : true;
              String? emailAddress = parts.length > 5 ? parts[5].trim() : null;
              String? phoneNumber = parts.length > 6 ? parts[6].trim() : null;
              String? emailAddressesStr =
                  parts.length > 7 ? parts[7].trim() : null;
              String? phoneNumbersStr =
                  parts.length > 8 ? parts[8].trim() : null;

              // Remove empty strings
              if (emailAddress?.isEmpty ?? true) emailAddress = null;
              if (phoneNumber?.isEmpty ?? true) phoneNumber = null;

              // Convert string-encoded lists to actual lists
              List<String> emailAddresses = _dbStringToStringList(
                emailAddressesStr,
              );
              List<String> phoneNumbers = _dbStringToStringList(
                phoneNumbersStr,
              );

              // If legacy single values aren't in the lists, add them
              if (emailAddress != null &&
                  !emailAddresses.contains(emailAddress)) {
                emailAddresses.add(emailAddress);
              }

              if (phoneNumber != null && !phoneNumbers.contains(phoneNumber)) {
                phoneNumbers.add(phoneNumber);
              }

              return Reminder(
                time: reminderTime,
                repeatType: RepeatTypeExtension.fromString(repeatTypeStr),
                repeatUntil: repeatUntilStr.isNotEmpty
                    ? DateTime.parse(repeatUntilStr)
                    : null,
                timezoneOffset: timezoneOffset,
                useScreenNotification: useScreenNotification,
                emailAddress: emailAddress,
                phoneNumber: phoneNumber,
                emailAddresses: emailAddresses,
                phoneNumbers: phoneNumbers,
              );
            }
            return null;
          })
          .whereType<Reminder>()
          .toList();
    } catch (e) {
      print('Error parsing reminders: $e');
      return [];
    }
  }

  Future<int> createMemo(
    int userId,
    String description,
    String? textContent,
    Uint8List? attachmentData,
    String? fileName,
    AttachmentType? attachmentType,
    List<Reminder> reminders,
  ) async {
    final conn = await _getConnection();
    try {
      print('Starting transaction for new MemrE creation');

      // Ensure schema is updated
      await updateSchema(userId);

      await conn.query('START TRANSACTION');

      // Insert MemrE and get the ID
      final memoResult = await conn.query(
        'INSERT INTO user_${userId}_memo (memo_desc, memo) VALUES (?, ?)',
        [description, textContent],
      );

      final memoId = memoResult.insertId;
      if (memoId == null) {
        throw Exception('Failed to get ID for newly created MemrE');
      }

      print('Created MemrE with ID: $memoId');

      // Handle attachment if exists
      if (attachmentData != null && attachmentType != null) {
        await conn.query(
          'INSERT INTO user_${userId}_attachment (memo_id, file_data, file_type, file_name) VALUES (?, ?, ?, ?)',
          [memoId, attachmentData, attachmentType.name, fileName],
        );
      }

      // Handle reminders
      for (var reminder in reminders) {
        // Prepare email addresses and phone numbers
        String? emailAddressesStr = _stringListToDbString(
          reminder.emailAddresses,
        );
        String? phoneNumbersStr = _stringListToDbString(reminder.phoneNumbers);

        final reminderResult = await conn.query(
          '''INSERT INTO user_${userId}_reminder 
             (reminder_time, repeat_type, repeat_until, timezone_offset, use_screen_notification, 
              email_address, phone_number, email_addresses, phone_numbers) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            reminder.time.toString(),
            reminder.repeatType.name,
            reminder.repeatUntil?.toString(),
            reminder.timezoneOffset ?? 0,
            reminder.useScreenNotification ? 1 : 0,
            reminder.emailAddress,
            reminder.phoneNumber,
            emailAddressesStr,
            phoneNumbersStr,
          ],
        );
        final reminderId = reminderResult.insertId;
        if (reminderId == null) {
          throw Exception('Failed to get ID for newly created reminder');
        }

        await conn.query(
          'INSERT INTO user_${userId}_memo_reminder (memo_id, reminder_id) VALUES (?, ?)',
          [memoId, reminderId],
        );
      }
      print('Committing transaction');
      await conn.query('COMMIT');

      print('Successfully created MemrE with ID: $memoId');
      return memoId; // Return the new MemrE ID
    } catch (e) {
      await conn.query('ROLLBACK');
      throw e;
    } finally {
      await conn.close();
    }
  }

  Future<void> updateMemo(
    int userId,
    int memoId,
    String description,
    String? textContent,
    Uint8List? attachmentData,
    String? fileName,
    AttachmentType? attachmentType,
    List<Reminder> reminders,
  ) async {
    final conn = await _getConnection();
    try {
      // Ensure schema is updated
      await updateSchema(userId);

      await conn.query('START TRANSACTION');

      // Update MemrE
      await conn.query(
        'UPDATE user_${userId}_memo SET memo_desc = ?, memo = ? WHERE memo_id = ?',
        [description, textContent, memoId],
      );

      // Handle attachment
      if (attachmentData != null && attachmentType != null) {
        await conn.query(
          'DELETE FROM user_${userId}_attachment WHERE memo_id = ?',
          [memoId],
        );
        await conn.query(
          'INSERT INTO user_${userId}_attachment (memo_id, file_data, file_type, file_name) VALUES (?, ?, ?, ?)',
          [memoId, attachmentData, attachmentType.name, fileName],
        );
      }

      // Update reminders
      // First delete old reminders
      final reminderResults = await conn.query(
        'SELECT reminder_id FROM user_${userId}_memo_reminder WHERE memo_id = ?',
        [memoId],
      );
      await conn.query(
        'DELETE FROM user_${userId}_memo_reminder WHERE memo_id = ?',
        [memoId],
      );
      for (var row in reminderResults) {
        await conn.query(
          'DELETE FROM user_${userId}_reminder WHERE reminder_id = ?',
          [row[0]],
        );
      }

      // Insert new reminders
      for (var reminder in reminders) {
        // Prepare email addresses and phone numbers
        String? emailAddressesStr = _stringListToDbString(
          reminder.emailAddresses,
        );
        String? phoneNumbersStr = _stringListToDbString(reminder.phoneNumbers);

        final reminderResult = await conn.query(
          '''INSERT INTO user_${userId}_reminder 
             (reminder_time, repeat_type, repeat_until, timezone_offset, use_screen_notification, 
              email_address, phone_number, email_addresses, phone_numbers) 
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            reminder.time.toString(),
            reminder.repeatType.name,
            reminder.repeatUntil?.toString(),
            reminder.timezoneOffset ?? 0,
            reminder.useScreenNotification ? 1 : 0,
            reminder.emailAddress, // Keep for backward compatibility
            reminder.phoneNumber, // Keep for backward compatibility
            emailAddressesStr,
            phoneNumbersStr,
          ],
        );
        final reminderId = reminderResult.insertId!;

        await conn.query(
          'INSERT INTO user_${userId}_memo_reminder (memo_id, reminder_id) VALUES (?, ?)',
          [memoId, reminderId],
        );
      }

      await conn.query('COMMIT');
    } catch (e) {
      print('Error in updateMemo: $e');
      await conn.query('ROLLBACK');
      rethrow;
    } finally {
      await conn.close();
    }
  }

  Future<void> deleteMemo(int userId, int memoId) async {
    final conn = await _getConnection();
    try {
      print('Starting transaction for memo deletion, ID: $memoId');
      await conn.query('START TRANSACTION');

      // Get reminder IDs to clean up
      final reminderResults = await conn.query(
        'SELECT reminder_id FROM user_${userId}_memo_reminder WHERE memo_id = ?',
        [memoId],
      );

      // Delete from junction table
      await conn.query(
        'DELETE FROM user_${userId}_memo_reminder WHERE memo_id = ?',
        [memoId],
      );

      // Delete reminders
      for (var row in reminderResults) {
        await conn.query(
          'DELETE FROM user_${userId}_reminder WHERE reminder_id = ?',
          [row[0]],
        );
      }

      // Delete attachment
      await conn.query(
        'DELETE FROM user_${userId}_attachment WHERE memo_id = ?',
        [memoId],
      );

      // Delete the MemrE
      await conn.query('DELETE FROM user_${userId}_memo WHERE memo_id = ?', [
        memoId,
      ]);

      await conn.query('COMMIT');
      print('Successfully deleted memo ID: $memoId');
    } catch (e) {
      print('Error in deleteMemo: $e');
      await conn.query('ROLLBACK');
      rethrow;
    } finally {
      await conn.close();
    }
  }
}
