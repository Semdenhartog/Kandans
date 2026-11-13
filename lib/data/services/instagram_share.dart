import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config.dart';

/// Opent Instagram met een afbeelding uit Kadans (Android, kanaal `kadans/instagram` in KadansChannels.kt).
///
/// Met een Meta App-ID (`META_APP_ID` in app_config.json) gaat de afbeelding rechtstreeks naar een nieuw verhaal;
/// een doorzichtige afbeelding komt er dan als sticker in, die je in Instagram over je eigen foto kunt zetten.
/// Zonder App-ID opent Instagram zijn eigen keuzescherm (Verhaal, Bericht, Reel of chat).
class InstagramShare {
  InstagramShare._();

  static const _channel = MethodChannel('kadans/instagram');

  /// Geeft false als Instagram niet op de telefoon staat of niet te openen is.
  static Future<bool> open(Uint8List png, {bool sticker = false}) async {
    if (!Platform.isAndroid) return false;
    try {
      // Map "deel" hoort bij android_extra/res/xml/kadans_share_paths.xml.
      final dir = Directory('${(await getTemporaryDirectory()).path}/deel');
      await dir.create(recursive: true);
      final file = File('${dir.path}/kadans-deelbeeld.png');
      await file.writeAsBytes(png, flush: true);
      final ok = await _channel.invokeMethod<bool>('share', {
        'path': file.path,
        'appId': AppConfig.metaAppId,
        'sticker': sticker,
        'top': '#13110E',
        'bottom': '#25201B',
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
