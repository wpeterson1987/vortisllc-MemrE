import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'notification_service.dart';

// Task names
const String reminderCheckTask = "com.memre.reminderCheck";

// Initialize workmanager
Future<void> initializeBackgroundTasks() async {
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // Set to false in production
  );

  // Register periodic task (minimum interval is 15 minutes)
  await Workmanager().registerPeriodicTask(
    "reminder-check-1", // Unique name
    reminderCheckTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  print("Background tasks registered");
}
// moved file back to /lib/services

// This must be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Background task started: $task");

    if (task == reminderCheckTask) {
      await checkForReminders();
    }

    return Future.value(true);
  });
}

Future<void> checkForReminders() async {
  try {
    // Get user ID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) {
      print("No user ID found, can't check reminders");
      return;
    }

    // For testing, show a notification
    await NotificationService.showNotification(
      id: 1,
      title: "MemrE Reminder Test",
      body: "Background task running at ${DateTime.now().toString()}",
    );

    // In a real implementation, you would check for due reminders
    // by calling your API or checking the database
  } catch (e) {
    print("Error checking reminders: $e");
  }
}
