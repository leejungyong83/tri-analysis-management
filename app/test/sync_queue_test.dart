import 'package:flutter_test/flutter_test.dart';
import 'package:tri_inspection_app/services/photo_service.dart';
import 'package:tri_inspection_app/services/sync_queue.dart';

void main() {
  group('재시도 백오프 (계획: 지수 백오프, 상한 1시간)', () {
    test('초기 30초, 시도마다 2배', () {
      expect(SyncQueue.backoff(0).inSeconds, 30);
      expect(SyncQueue.backoff(1).inSeconds, 60);
      expect(SyncQueue.backoff(2).inSeconds, 120);
      expect(SyncQueue.backoff(3).inSeconds, 240);
    });

    test('상한 1시간 초과 금지', () {
      expect(SyncQueue.backoff(7).inSeconds, 3600);
      expect(SyncQueue.backoff(10).inSeconds, 3600);
      expect(SyncQueue.backoff(100).inSeconds, 3600);
    });

    test('경고 임계: 10회 연속 실패', () {
      expect(SyncQueue.warnAfterFailures, 10);
    });
  });

  group('사진 압축 상한 (계획: ≤1.3MB — base64 팽창 후 2MB 이내)', () {
    test('압축 목표 상수 = 1.3MB', () {
      expect(PhotoService.maxBytes, 1300 * 1024);
      // base64 팽창(4/3) 후에도 서버 요청 상한 2MB 이내인지 수치 검증
      final base64Size = (PhotoService.maxBytes * 4 / 3).ceil();
      expect(base64Size, lessThan(2 * 1024 * 1024));
    });
  });
}
