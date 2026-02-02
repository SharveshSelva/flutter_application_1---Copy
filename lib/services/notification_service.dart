import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      if (_initialized) return;
      
      // Initialize timezones FIRST
      tz.initializeTimeZones();
      
      // Set local timezone - THIS IS CRITICAL
      final tz.Location loc = tz.getLocation('Asia/Kolkata');
      tz.setLocalLocation(loc);
      debugPrint('🌍 Timezone initialized: ${loc.name}');
      debugPrint('🕐 Current local time: ${tz.TZDateTime.now(tz.local)}');
      
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification tapped: ${details.payload}');
        },
      );

      // Create notification channel with HIGH importance
      if (defaultTargetPlatform == TargetPlatform.android) {
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'task_reminders_v2',
          'Task Reminders',
          description: 'Notifications for task reminders',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFF00FF00),
        );

        final androidPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        await androidPlugin?.createNotificationChannel(channel);
        
        debugPrint('✅ Notification channel created: ${channel.id}');
      }

      _initialized = true;
      debugPrint('✅ NotificationService initialized');
    }
  }

  static Future<bool> requestPermissions() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
        if (androidPlugin != null) {
          final notificationGranted = await androidPlugin.requestNotificationsPermission();
          debugPrint('📱 Notification permission: $notificationGranted');
          
          // Request exact alarm permission - CRITICAL for scheduled notifications
          final exactAlarmGranted = await androidPlugin.requestExactAlarmsPermission();
          debugPrint('⏰ Exact alarm permission: $exactAlarmGranted');
          
          if (exactAlarmGranted == false) {
            debugPrint('⚠️ WARNING: Exact alarms not granted. Scheduled notifications may not work!');
          }
          
          return (notificationGranted ?? false) && (exactAlarmGranted ?? false);
        }
        return false;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        
        final granted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    }
    return false;
  }

  static Future<void> scheduleTaskReminder({
    required String taskTitle,
    required DateTime reminderTime,
  }) async {
    print('--- 1. [SERVICE] scheduleTaskReminder CALLED ---');
    print('--- 2. [SERVICE] Input Time: $reminderTime');
    print('--- 3. [SERVICE] Task Title: $taskTitle');
    try {
     if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      
      if (!_initialized) {
        debugPrint('⚠️ NotificationService not initialized, initializing now...');
        await initialize();
      }
      final dynamic timeZone = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timeZone?.toString() ?? 'UTC';
      print('--- 5. [SERVICE] Detected Timezone: $timeZoneName');
      final tz.Location location = tz.getLocation(timeZoneName);
      print('--- 6. [SERVICE] tz.Location object: $location');
      final now = DateTime.now();
      if (reminderTime.isBefore(now)) {
        throw Exception('Cannot schedule notification in the past. Reminder time: $reminderTime, Current time: $now');
      }
      print('--- 9. [SERVICE] Time is valid (in the future).');
      final int notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'task_reminders_v2',
        'Task Reminders',
        channelDescription: 'Notifications for task reminders',
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: Color(0xFF00FF00),
        ledOnMs: 1000,
        ledOffMs: 500,
        ticker: 'Task Reminder',
        styleInformation: BigTextStyleInformation(''),
        visibility: NotificationVisibility.public,
        // Add these for better reliability
        autoCancel: false,
        ongoing: false,
        timeoutAfter: null,
      );

      const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      // Convert to TZ datetime using local timezone
      final tz.TZDateTime scheduledDate = tz.TZDateTime.from(reminderTime, location);
      final tz.TZDateTime nowTz = tz.TZDateTime.now(location);
      print('--- 7. [SERVICE] Now (TZDateTime): $nowTz');
      print('--- 8. [SERVICE] Scheduled (TZDateTime): $scheduledDate');
      debugPrint('⏰ ==================== SCHEDULING DEBUG ====================');
      debugPrint('🌍 Timezone Name: $timeZoneName');
      debugPrint('📅 Current time (DateTime): $now');
      debugPrint('📅 Current time (TZ): $nowTz');
      debugPrint('🎯 Scheduled time (DateTime): $reminderTime');
      debugPrint('🎯 Scheduled time (TZ): $scheduledDate');
      debugPrint('⏱️ Time difference: ${scheduledDate.difference(nowTz).inSeconds} seconds');
      debugPrint('🆔 Notification ID: $notificationId');
      
      if (scheduledDate.isBefore(nowTz)) {
        print('❌❌❌ ERROR: SCHEDULED TIME IS IN THE PAST! ❌❌❌');
        print('--- Difference: ${scheduledDate.difference(nowTz).inMilliseconds} ms');
        throw Exception('Scheduled time is in the past! This should not happen.');
      }
      print('--- 9. [SERVICE] Time is valid (in the future).');

      try {
        print('--- 10. [SERVICE] Scheduling with ID: $notificationId');
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Task Reminder ⏰',
          taskTitle,
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );

        debugPrint('✅ Notification scheduled successfully with ID: $notificationId');
      } catch (e) {
        debugPrint('❌ Error during zonedSchedule: $e');
        rethrow;
      }
      print('--- 11. [SERVICE] zonedSchedule() call SUCCEEDED.');
      // Verify it was scheduled
      await Future.delayed(const Duration(milliseconds: 500)); // Small delay to ensure it's registered
      final pending = await _notificationsPlugin.pendingNotificationRequests();
      print('--- 12. [SERVICE] Total pending notifications: ${pending.length}');
      debugPrint('📋 Total pending notifications after scheduling: ${pending.length}');
      
      bool found = false;
      for (var p in pending) {
        debugPrint('   - ID: ${p.id}, Title: ${p.title}, Body: ${p.body}');
        if (p.id == notificationId) {
          found = true;
          debugPrint('   ✅ Our notification IS in the pending list!');
        }
      }
      
      if (!found) {
        debugPrint('⚠️ WARNING: Notification was NOT found in pending list!');
        debugPrint('⚠️ This means it may not trigger. Check exact alarm permissions.');
      }else{
        print('✅✅✅ SUCCESS: Notification IS in the pending list! ✅✅✅');
      }
      
      debugPrint('========================================================');
    } else {
      throw UnsupportedError('Notifications only supported on Android/iOS');
      }
    }catch(e){
      print('❌❌❌ [SERVICE] FAILED WITH EXCEPTION: $e ❌❌❌');
      rethrow;
    }
  }

  // Test immediate notification
  static Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'task_reminders_v2',
      'Task Reminders',
      channelDescription: 'Notifications for task reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      ticker: 'Task Reminder',
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      details,
    );

    debugPrint('✅ Immediate notification shown with ID: $id');
  }

  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  static Future<void> debugPendingNotifications() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final pending = await _notificationsPlugin.pendingNotificationRequests();
        debugPrint('📋 Total pending notifications: ${pending.length}');
        
        if (pending.isEmpty) {
          debugPrint('   ℹ️ No pending notifications scheduled');
        } else {
          for (var p in pending) {
            debugPrint('   - ID: ${p.id}');
            debugPrint('     Title: ${p.title}');
            debugPrint('     Body: ${p.body}');
            debugPrint('     Payload: ${p.payload}');
            debugPrint('     ---');
          }
        }
        
        // Also check active notifications (currently showing)
        if (defaultTargetPlatform == TargetPlatform.android) {
          final androidPlugin = _notificationsPlugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          
          final activeNotifications = await androidPlugin?.getActiveNotifications();
          if (activeNotifications != null) {
            debugPrint('🔔 Active notifications: ${activeNotifications.length}');
            for (var notification in activeNotifications) {
              debugPrint('   - ID: ${notification.id}, Title: ${notification.title}');
            }
          }
        }
      } catch (e) {
        debugPrint('❌ Error checking pending notifications: $e');
      }
    } else {
      debugPrint('⚠️ Notifications not supported on this platform');
    }
  }
}