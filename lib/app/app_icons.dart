import 'package:flutter/material.dart';

import 'theme_look.dart';
import 'theme_style.dart';

/// One icon in its outlined and filled forms.
class AppIconPair {
  const AppIconPair(this.outlined, this.filled);

  final IconData outlined;
  final IconData filled;

  IconData forStyle(IconStyle style) => style == IconStyle.filled ? filled : outlined;
}

/// The icons the shell and the common screens use, each in both forms, so
/// a theme's [IconStyle] can switch them all at once.
abstract final class AppIcons {
  static const hosts = AppIconPair(Icons.dns_outlined, Icons.dns);
  static const sessions = AppIconPair(Icons.terminal_outlined, Icons.terminal);
  static const snippets = AppIconPair(Icons.bolt_outlined, Icons.bolt);
  static const keychain = AppIconPair(Icons.key_outlined, Icons.key);
  static const settings = AppIconPair(Icons.tune_outlined, Icons.tune);
  static const keyboard = AppIconPair(Icons.keyboard_outlined, Icons.keyboard);
  static const keyboardAlt = AppIconPair(Icons.keyboard_alt_outlined, Icons.keyboard_alt);
  static const folder = AppIconPair(Icons.folder_outlined, Icons.folder);
  static const download = AppIconPair(Icons.file_download_outlined, Icons.file_download);
  static const fileOpen = AppIconPair(Icons.file_open_outlined, Icons.file_open);
  static const palette = AppIconPair(Icons.palette_outlined, Icons.palette);
  static const backup = AppIconPair(Icons.backup_outlined, Icons.backup);
  static const vpnKey = AppIconPair(Icons.vpn_key_outlined, Icons.vpn_key);
  static const verifiedUser = AppIconPair(Icons.verified_user_outlined, Icons.verified_user);
  static const memory = AppIconPair(Icons.memory_outlined, Icons.memory);
  static const gavel = AppIconPair(Icons.gavel_outlined, Icons.gavel);
  static const image = AppIconPair(Icons.image_outlined, Icons.image);
  static const style = AppIconPair(Icons.style_outlined, Icons.style);
}

/// An [Icon] drawn in the active theme's icon style. With [selected] it is
/// always filled, the way a chosen navigation item shows.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.selected = false, this.size, this.color, this.semanticLabel});

  final AppIconPair icon;
  final bool selected;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final style = AppStyleTheme.of(context).style.icons;
    final data = selected ? icon.filled : icon.forStyle(style);
    return Icon(data, size: size, color: color, semanticLabel: semanticLabel);
  }
}
