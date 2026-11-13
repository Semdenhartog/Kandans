import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config.dart';

/// Zet beelden één voor één om in een mp4 (Android, kanaal `kadans/video` in KadansChannels.kt).
class VideoEncoder {
  VideoEncoder._(this.path);

  static const _channel = MethodChannel('kadans/video');
  final String path;

  /// Map "deel" hoort bij android_extra/res/xml/kadans_share_paths.xml.
  static Future<VideoEncoder> begin({required int width, required int height, required int fps}) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/deel');
    await dir.create(recursive: true);
    final path = '${dir.path}/kadans-route.mp4';
    await _channel.invokeMethod('begin', {'path': path, 'width': width, 'height': height, 'fps': fps});
    return VideoEncoder._(path);
  }

  Future<void> frame(Uint8List rgba, int index) => _channel.invokeMethod('frame', {'rgba': rgba, 'index': index});

  Future<String> finish() async {
    await _channel.invokeMethod('finish');
    return path;
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod('cancel');
    } catch (_) {}
  }

  /// Opent Instagram met de video (keuzescherm of rechtstreeks naar een verhaal, zie [InstagramShare]).
  static Future<bool> openInInstagram(String path) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await const MethodChannel('kadans/instagram').invokeMethod<bool>('share', {
        'path': path,
        'appId': AppConfig.metaAppId,
        'sticker': false,
        'mime': 'video/mp4',
        'top': '#13110E',
        'bottom': '#25201B',
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
