import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A starting folder on this device.
class PhoneRoot {
  const PhoneRoot({required this.label, required this.path, required this.icon, this.note});

  final String label;
  final String path;
  final IconData icon;

  /// A line under the label, for example what is kept there.
  final String? note;
}

/// The folders on this device the app can show, and Android's "all
/// files" access, which reading other apps' files needs. The native side
/// is StorageChannel.kt.
abstract final class PhoneStorage {
  static const channel = MethodChannel('multiplex/storage');

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// The app's own files are always there; the whole phone storage only
  /// once the user allowed all-files access.
  static Future<List<PhoneRoot>> roots() async {
    final documents = await getApplicationDocumentsDirectory();
    final roots = [
      PhoneRoot(label: 'App files', path: documents.path, icon: Icons.folder_special_outlined, note: 'Downloads and copies kept by Multiplex'),
    ];
    if (_android) {
      if (await hasAllFilesAccess()) {
        final storage = await channel.invokeMethod<String>('storageRoot');
        if (storage != null) roots.add(PhoneRoot(label: 'Phone storage', path: storage, icon: Icons.smartphone, note: 'Download, Documents, DCIM and the rest'));
      }
    } else {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) roots.add(PhoneRoot(label: 'Home folder', path: home, icon: Icons.home_outlined));
    }
    return roots;
  }

  /// True when the app may read and write every file in shared storage.
  static Future<bool> hasAllFilesAccess() async {
    if (!_android) return true;
    try {
      return await channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Android's settings page where the user can allow it. The
  /// answer is only known when they come back, so check again then.
  static Future<void> askAllFilesAccess() async {
    if (!_android) return;
    await channel.invokeMethod<void>('askAllFilesAccess');
  }
}
