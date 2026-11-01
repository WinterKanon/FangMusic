import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/services/sleep_timer_service.dart';

void main() {
  final service = SleepTimerService.instance;

  setUp(() => service.cancel());

  test('播完当前歌曲模式：到点进入 pending，消费后结束', () async {
    var playing = true;
    service.isPlaying = () => playing;
    service.start(const Duration(milliseconds: 30), SleepTimerMode.finishCurrent);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(service.pendingPause, isTrue);
    expect(service.active, isTrue);
    expect(service.consumePendingPause(), isTrue);
    expect(service.pendingPause, isFalse);
    expect(service.active, isFalse);
  });

  test('到点时已暂停：结束定时，不 pending', () async {
    service.isPlaying = () => false;
    service.start(const Duration(milliseconds: 20), SleepTimerMode.finishCurrent);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(service.pendingPause, isFalse);
    expect(service.active, isFalse);
  });

  test('立即暂停模式：到点调用暂停回调并结束', () async {
    var paused = false;
    service.isPlaying = () => true;
    service.pausePlayer = () async => paused = true;
    service.start(const Duration(milliseconds: 20), SleepTimerMode.pauseNow);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(paused, isTrue);
    expect(service.active, isFalse);
  });
}
