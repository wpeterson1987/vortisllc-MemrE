import 'dart:async';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SimpleNotificationManager {
  // Initialize notifications
  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'memre_reminders',
          channelName: 'MemrE Reminders',
          channelDescription: 'Notifications for MemrE reminders',
          defaultColor: Color(0xFF2196F3),
          ledColor: Colors.blue,
          importance: NotificationImportance.High,
          defaultPrivacy: NotificationPrivacy.Private,
        ),
        NotificationChannel(
          channelKey: 'scheduled_channel',
          channelName: 'Scheduled Reminders',
          channelDescription: 'Channel for scheduled reminders',
          defaultColor: Color(0xFF2196F3),
          ledColor: Colors.blue,
          importance: NotificationImportance.High,
          defaultPrivacy: NotificationPrivacy.Private,
        )
      ],
    );

    // Request notification permissions
    await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });
  }

  // Schedule a notification
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'scheduled_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
      ),
      schedule: NotificationCalendar(
        year: scheduledDate.year,
        month: scheduledDate.month,
        day: scheduledDate.day,
        hour: scheduledDate.hour,
        minute: scheduledDate.minute,
        second: scheduledDate.second,
        preciseAlarm: true,
      ),
    );
  }

  // Show an immediate notification
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'memre_reminders',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
      ),
    );
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await AwesomeNotifications().cancelAll();
  }

  // Set up notification action listeners
  static Future<void> setupNotificationListeners(
      void Function(ReceivedNotification) onNotificationReceived) async {
    // Listen to notification creation events
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
      onNotificationCreatedMethod: _onNotificationCreated,
      onNotificationDisplayedMethod: _onNotificationDisplayed,
      onDismissActionReceivedMethod: _onDismissActionReceived,
    );
  }

  // Notification callbacks
  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction receivedAction) async {
    // Handle notification tap
    print('Notification action received: ${receivedAction.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> _onNotificationCreated(
      ReceivedNotification receivedNotification) async {
    print('Notification created: ${receivedNotification.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> _onNotificationDisplayed(
      ReceivedNotification receivedNotification) async {
    print('Notification displayed: ${receivedNotification.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> _onDismissActionReceived(
      ReceivedAction receivedAction) async {
    print('Notification dismissed: ${receivedAction.id}');
  }
}
