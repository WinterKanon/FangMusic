import 'package:flutter_test/flutter_test.dart';

import 'package:fs_music_app/services/audio_scanner_service.dart';

void main() {
  group('resolveDirectoryPath（文件夹 URI → 真实路径）', () {
    test('编码冒号（%3A）的 tree URI → 内部存储路径', () {
      expect(
        AudioScannerService.resolveDirectoryPath(
          'content://com.android.externalstorage.documents/tree/primary%3AMusic',
        ),
        '/storage/emulated/0/Music',
      );
    });

    test('未编码冒号的 tree URI → 内部存储路径', () {
      expect(
        AudioScannerService.resolveDirectoryPath(
          'content://com.android.externalstorage.documents/tree/primary:Music',
        ),
        '/storage/emulated/0/Music',
      );
    });

    test('根目录 tree URI → 内部存储根', () {
      expect(
        AudioScannerService.resolveDirectoryPath(
          'content://com.android.externalstorage.documents/tree/primary%3A',
        ),
        '/storage/emulated/0/',
      );
    });

    test('子目录含斜杠编码 → 解析为完整相对路径', () {
      expect(
        AudioScannerService.resolveDirectoryPath(
          'content://com.android.externalstorage.documents/tree/primary%3AMusic%2FMySongs',
        ),
        '/storage/emulated/0/Music/MySongs',
      );
    });

    test('已是真实路径 → 原样返回', () {
      expect(
        AudioScannerService.resolveDirectoryPath('/storage/emulated/0/Music'),
        '/storage/emulated/0/Music',
      );
    });

    test('SD 卡（secondary）→ null（暂不支持）', () {
      expect(
        AudioScannerService.resolveDirectoryPath(
          'content://com.android.externalstorage.documents/tree/secondary%3A1234-ABCD',
        ),
        isNull,
      );
    });

    test('其他 provider → null', () {
      expect(
        AudioScannerService.resolveDirectoryPath(
          'content://com.android.providers.downloads.documents/tree/downloads',
        ),
        isNull,
      );
    });

    test('无效输入 → null', () {
      expect(AudioScannerService.resolveDirectoryPath('not a uri'), isNull);
    });
  });
}
