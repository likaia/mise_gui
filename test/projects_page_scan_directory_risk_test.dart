import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/features/projects/presentation/projects_page.dart';

void main() {
  test('flags system and disk roots as risky scan directories', () {
    expect(scanDirectoryRiskForPath('/')?.message, contains('系统根目录'));
    expect(
      scanDirectoryRiskForPath('/Volumes/Macintosh HD')?.message,
      contains('macOS 磁盘卷根目录'),
    );
    expect(
      scanDirectoryRiskForPath('/media/alex/Backup')?.message,
      contains('Linux 挂载磁盘根目录'),
    );
    expect(
      scanDirectoryRiskForPath(r'C:\')?.message,
      contains('Windows 磁盘根目录'),
    );
    expect(
      scanDirectoryRiskForPath(r'\\server\share')?.message,
      contains('网络共享根目录'),
    );
  });

  test('does not flag normal project workspace directories', () {
    expect(scanDirectoryRiskForPath('/Users/alex/Projects'), isNull);
    expect(scanDirectoryRiskForPath('/home/alex/work/mise_gui'), isNull);
    expect(scanDirectoryRiskForPath(r'D:\Projects\mise_gui'), isNull);
  });
}
