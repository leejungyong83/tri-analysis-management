import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class CapturedPhoto {
  final int rackIndex; // 1~5 (어느 Rack의 사진인지)
  final String photoUuid;
  final Uint8List jpegBytes;

  const CapturedPhoto({
    required this.rackIndex,
    required this.photoUuid,
    required this.jpegBytes,
  });
}

/// 카메라 촬영 + 압축. Rack마다 1장(총 5장) 촬영한다 (사용자 지시).
///
/// 압축 목표 ≤1.3MB — base64 팽창(~33%) 후에도 서버 요청 상한 2MB 이내 보장.
/// photoUUID는 촬영 시점에 부여되어 Drive 파일명 멱등키가 된다.
class PhotoService {
  static const int maxBytes = 1300 * 1024;
  static const _uuid = Uuid();

  final ImagePicker _picker = ImagePicker();

  Future<CapturedPhoto?> captureAndCompress(int rackIndex) async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (x == null) return null;
    var bytes = await x.readAsBytes();
    bytes = await compressIfNeeded(bytes);
    return CapturedPhoto(
      rackIndex: rackIndex,
      photoUuid: _uuid.v4(),
      jpegBytes: bytes,
    );
  }

  /// 1.3MB 초과 시 리사이즈+품질 하향 루프 (웹은 pickImage의 imageQuality가
  /// 무시될 수 있어 pure Dart 폴백이 필수).
  static Future<Uint8List> compressIfNeeded(Uint8List bytes) async {
    if (bytes.length <= maxBytes) return bytes;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    var work = decoded.width > 1280 || decoded.height > 1280
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1280 : null,
            height: decoded.height > decoded.width ? 1280 : null,
          )
        : decoded;

    for (var quality = 80; quality >= 40; quality -= 10) {
      final out = Uint8List.fromList(img.encodeJpg(work, quality: quality));
      if (out.length <= maxBytes) return out;
      if (quality == 40) return out; // 최저 품질 결과라도 반환 (서버 상한이 최종 방어)
    }
    return bytes;
  }
}
