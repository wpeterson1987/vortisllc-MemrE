import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();

  factory PermissionService() {
    return _instance;
  }

  PermissionService._internal();

  Future<bool> checkSMSPermission() async {
    var status = await Permission.sms.status;
    return status.isGranted;
  }

  Future<bool> requestSMSPermission() async {
    var status = await Permission.sms.request();
    return status.isGranted;
  }

  // Show permission rational dialog
  Future<bool> showPermissionRationale(
      BuildContext context, String permissionType) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$permissionType Permission Required'),
            content: Text(
                'This app needs $permissionType permission to send notifications through $permissionType. '
                'Would you like to grant permission?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not Now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
