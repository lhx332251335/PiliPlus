import 'package:PiliPlus/utils/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same release tag is current even when published after APK build', () {
    expect(
      Update.isCurrentRelease(
        '2.2.1-prm.2',
        200,
        version: '2.2.1-prm.2',
        buildTime: 100,
      ),
      isTrue,
    );
  });

  test('a different later release remains an update', () {
    expect(
      Update.isCurrentRelease(
        '2.2.1-prm.3',
        200,
        version: '2.2.1-prm.2',
        buildTime: 100,
      ),
      isFalse,
    );
  });

  test('older or same-time release retains the original time guard', () {
    for (final time in [99, 100]) {
      expect(
        Update.isCurrentRelease(
          '2.2.1-prm.1',
          time,
          version: '2.2.1-prm.2',
          buildTime: 100,
        ),
        isTrue,
      );
    }
  });
}
