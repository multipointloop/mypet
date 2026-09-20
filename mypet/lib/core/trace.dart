import 'dart:io';

/// Synchronous file trace - survives native crashes so the LAST line shows
/// exactly which call killed the process.
class Trace {
  static void log(String msg) {
    try {
      File('E:/desktop pet/dev/pet_trace.log').writeAsStringSync(
          '${DateTime.now().toIso8601String().substring(11, 23)} $msg\n',
          mode: FileMode.append);
    } catch (_) {}
  }
}
