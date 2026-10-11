import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课表自定义背景：本机图片路径 + 淡显程度。
///
/// 存 SharedPreferences 的独立键上（**不进云端课表**——课表 store 会整体
/// 上传同步，本地文件路径同步出去没有意义）。
class TtBackground extends ChangeNotifier {
  TtBackground._();
  static final TtBackground I = TtBackground._();

  static const _kPath = 'tt_background_path';
  static const _kOpacity = 'tt_background_opacity';

  /// 默认淡显：照片垫在课表底下要浅到不干扰读课，0.16 是稳妥起点。
  static const double defaultOpacity = 0.16;
  static const double minOpacity = 0.05;
  static const double maxOpacity = 0.5;

  String? path;
  double opacity = defaultOpacity;
  bool loaded = false;

  /// 供测试写入状态；正常流程走 [load] / [set]。
  @visibleForTesting
  void debugFill({String? path, double opacity = defaultOpacity}) {
    this.path = path;
    this.opacity = opacity;
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    path = sp.getString(_kPath);
    opacity = sp.getDouble(_kOpacity) ?? defaultOpacity;
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    if (path == null) {
      await sp.remove(_kPath);
    } else {
      await sp.setString(_kPath, path!);
    }
    await sp.setDouble(_kOpacity, opacity);
  }

  /// 设置背景图路径；换图 / 清除时删掉旧的本机副本，别攒一串相册拷贝。
  Future<void> set(String? newPath) async {
    if (newPath == path) return;
    final old = path;
    path = newPath;
    await _persist();
    notifyListeners();
    if (old != null && old != newPath) {
      try {
        final f = File(old);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// 调淡显程度（只在有背景图时有意义，滑块按 path 是否为空决定可用）。
  Future<void> setOpacity(double v) async {
    opacity = v.clamp(minOpacity, maxOpacity);
    await _persist();
    notifyListeners();
  }

  /// 把图库里选中的图拷进应用目录（picker 给的是临时文件，随时会被清掉）。
  Future<String?> copyIntoAppDir(String pickedPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = pickedPath.contains('.')
          ? pickedPath.substring(pickedPath.lastIndexOf('.'))
          : '.jpg';
      final target =
          File('${dir.path}/tt_background_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(pickedPath).copy(target.path);
      return target.path;
    } catch (_) {
      return null; // 拷贝失败就没有背景，不影响课表本身
    }
  }
}
