import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/repositories/dashboard_repository.dart';

void main() {
  group('dashboard system info parsers', () {
    test('parses x64 Linux cpu model', () {
      final model = parseLinuxCpuModel('''
processor   : 0
vendor_id   : GenuineIntel
model name  : Intel(R) Core(TM) i7-12700K
cpu MHz     : 3600.000
''');

      expect(model, 'Intel(R) Core(TM) i7-12700K');
    });

    test('parses ARM Linux cpu model fallback', () {
      final model = parseLinuxCpuModel('''
processor   : 0
BogoMIPS    : 108.00
Hardware    : BCM2835
''');

      expect(model, 'BCM2835');
    });

    test('parses Linux memory total', () {
      final bytes = parseLinuxMemoryBytes('''
MemTotal:       32768000 kB
MemFree:         1024000 kB
''');

      expect(bytes, 32768000 * 1024);
      expect(formatByteCount(bytes!), '31 GB');
    });

    test('parses POSIX df output', () {
      final diskInfo = parsePosixDfKilobytes('''
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk3s5 976490576 390596230 585894346 40% /
''');

      expect(diskInfo, isNotNull);
      expect(diskInfo!.totalBytes, 976490576 * 1024);
      expect(diskInfo.availableBytes, 585894346 * 1024);
    });

    test('parses Windows PowerShell key value output', () {
      final values = parseKeyValueOutput('''
FreeSpace=499122176000\r
Size=1000202273280\r
''');

      expect(values['FreeSpace'], '499122176000');
      expect(values['Size'], '1000202273280');
    });

    test('formats byte counts', () {
      expect(formatByteCount(512), '512 B');
      expect(formatByteCount(1024), '1 KB');
      expect(formatByteCount(1536), '1.5 KB');
      expect(formatByteCount(16 * 1024 * 1024 * 1024), '16 GB');
    });
  });
}
