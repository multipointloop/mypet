import 'package:flutter_test/flutter_test.dart';
import 'package:mypet/platform/win/window_service.dart';

void main() {
  test('简易调整栏 id 映射到对应动作', () {
    var scale = 0.0;
    var through = 0;
    var settings = 0;
    var quit = 0;
    void dispatch(int id) => dispatchQuickMenu(
          id,
          onScaleDelta: (d) => scale += d,
          onToggleClickThrough: () => through++,
          onToggleSettings: () => settings++,
          onQuit: () => quit++,
        );

    dispatch(0);
    dispatch(1);
    expect(scale, closeTo(0.0, 1e-9));
    dispatch(2);
    dispatch(3);
    dispatch(4);
    dispatch(99);
    expect(through, 1);
    expect(settings, 1);
    expect(quit, 1);
  });
}
