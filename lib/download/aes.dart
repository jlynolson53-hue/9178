import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// HLS 标准 AES-128-CBC + PKCS7 解密（在后台 isolate 中调用）
Uint8List aes128Decrypt(Uint8List data, Uint8List key, Uint8List iv) {
  try {
    final c = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(false, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null));
    return c.process(data);
  } catch (_) {
    // 个别源末尾没有正确填充：退回无填充解密
    final c = CBCBlockCipher(AESEngine())..init(false, ParametersWithIV(KeyParameter(key), iv));
    final len = data.length - data.length % 16;
    final out = Uint8List(len);
    for (var off = 0; off < len; off += 16) {
      c.processBlock(data, off, out, off);
    }
    return out;
  }
}
