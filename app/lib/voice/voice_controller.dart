import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/kiosk_platform.dart';

enum VoiceState { idle, listening, thinking, speaking, error }

/// One push-to-talk turn at a time against Home Assistant's Assist pipeline (docs/VOICE.md).
/// Audio frames come from the platform, answers go back to the platform for playback; everything in between
/// is the wire protocol. Kept free of the widget tree and of the socket (both are injected) so it can be tested.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.platform,
    required this.send,
    required this.baseUrl,
    this.dismissAfter = const Duration(seconds: 4),
    this.silenceTimeout = const Duration(seconds: 20),
  });

  final KioskPlatform platform;

  /// Sends one protocol message; false when there is no connection to Home Assistant.
  final bool Function(Map<String, dynamic> message) send;

  /// The address Home Assistant is reached at right now (answers are fetched from there), or null.
  final String? Function() baseUrl;
  final Duration dismissAfter;
  final Duration silenceTimeout;

  VoiceState state = VoiceState.idle;
  String? session;
  String transcript = '';
  String answer = '';

  /// Error code (`mic_permission`, `not_connected`, `stt-no-text-recognized`, ...) while [state] is error.
  String? errorCode;
  String? errorMessage;
  double level = 0;
  bool get active => state != VoiceState.idle;

  Timer? _dismiss;
  Timer? _watchdog;
  bool _recording = false;
  int _counter = 0;

  /// Starts a turn. Returns null, or the error code (also shown in the UI).
  /// [wakeWord] is the phrase that started it (Home Assistant gets it with the run).
  Future<String?> listen({String? wakeWord}) async {
    if (active) await cancel(silent: true); // barge-in
    _dismiss?.cancel();
    final id = 'v${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    session = id;
    transcript = answer = '';
    errorCode = errorMessage = null;
    level = 0;
    if (baseUrl() == null ||
        !send({
          'type': 'voice',
          'action': 'start',
          'session': id,
          'wake_word': ?wakeWord,
        })) {
      return _fail('not_connected');
    }
    state = VoiceState.listening;
    notifyListeners();
    unawaited(platform.showUi('/voice'));
    final err = await platform.voiceStart(id);
    if (err != null) {
      send({'type': 'voice', 'action': 'cancel', 'session': id});
      return _fail(err);
    }
    _recording = true;
    _armWatchdog();
    return null;
  }

  /// The user is done talking (button) or the recording hit its limit: Home Assistant gets the end of the audio.
  Future<void> stopListening() async {
    final id = session;
    if (id == null || !_recording) return;
    await _stopRecording();
    send({'type': 'voice', 'action': 'stop', 'session': id});
  }

  /// Aborts the turn (also stops the answer if it is being spoken).
  Future<void> cancel({bool silent = false}) async {
    final id = session;
    if (id != null) send({'type': 'voice', 'action': 'cancel', 'session': id});
    await _stopRecording();
    await platform.voiceStopPlayback();
    _watchdog?.cancel();
    session = null;
    state = VoiceState.idle;
    level = 0;
    notifyListeners();
    if (!silent) _closeUi();
  }

  /// Announcement from Home Assistant: the pre-announce sound, then [url]; completes when it has been played.
  Future<void> announce({
    required String url,
    String message = '',
    String? preannounceUrl,
  }) async {
    if (active) await cancel(silent: true);
    _dismiss?.cancel();
    session = null;
    transcript = '';
    answer = message;
    errorCode = errorMessage = null;
    state = VoiceState.speaking;
    notifyListeners();
    unawaited(platform.showUi('/voice'));
    try {
      for (final u in [?preannounceUrl, url]) {
        final abs = _absolute(u);
        if (abs == null) throw StateError('not_connected');
        final err = await platform.voicePlay(abs);
        if (err != null) throw StateError(err);
      }
    } finally {
      state = VoiceState.idle;
      notifyListeners();
      _scheduleClose();
    }
  }

  /// The tablet lost Home Assistant: nobody will answer this turn.
  void onDisconnected() {
    if (active && session != null) unawaited(cancel());
  }

  // --- from the platform ---------------------------------------------------------------------------

  void onPlatformEvent(PlatformEvent e) {
    final id = e.data['session'] as String?;
    if (id == null || id != session) return;
    switch (e.type) {
      case 'voice_frame':
        send({
          'type': 'voice',
          'action': 'audio',
          'session': id,
          'data': e.data['data'],
        });
        level = (e.data['level'] as num?)?.toDouble() ?? 0;
        notifyListeners();
      case 'voice_record_timeout':
        unawaited(stopListening());
      case 'voice_record_error':
        _recording = false;
        send({'type': 'voice', 'action': 'cancel', 'session': id});
        _fail(e.data['code'] as String? ?? 'mic_failed');
    }
  }

  // --- from Home Assistant -------------------------------------------------------------------------

  void onVoiceEvent(Map<String, dynamic> msg) {
    final id = msg['session'] as String?;
    if (id == null || id != session) return; // an event of a cancelled turn
    final data = Map<String, dynamic>.from((msg['data'] as Map?) ?? const {});
    _armWatchdog();
    switch (msg['event']) {
      case 'stt-end':
        transcript = (data['text'] as String?) ?? '';
        state = VoiceState.thinking;
        unawaited(_stopRecording());
        send({'type': 'voice', 'action': 'stop', 'session': id});
        notifyListeners();
      case 'intent-end':
        answer = (data['text'] as String?) ?? '';
        notifyListeners();
      case 'tts-end':
        unawaited(_speak(id, (data['url'] as String?) ?? ''));
      case 'run-end':
        if (state != VoiceState.speaking && state != VoiceState.error) {
          _finish();
        }
      case 'error':
        unawaited(_stopRecording());
        _fail(
          (data['code'] as String?) ?? 'unknown',
          message: data['message'] as String?,
        );
    }
  }

  // --- internals -----------------------------------------------------------------------------------

  Future<void> _speak(String id, String url) async {
    final abs = _absolute(url);
    if (abs == null) return _finish();
    state = VoiceState.speaking;
    _watchdog?.cancel();
    notifyListeners();
    final err = await platform.voicePlay(abs);
    if (session != id) return; // cancelled while speaking
    send({'type': 'voice', 'action': 'played', 'session': id});
    if (err != null && err != 'interrupted') {
      _fail(err);
    } else {
      _finish();
    }
  }

  String? _absolute(String url) {
    final base = baseUrl();
    if (base == null || url.isEmpty) return null;
    // Home Assistant may name itself by an address this tablet cannot reach (its internal URL while we are
    // away): keep the path and ask the address we are connected through
    final u = Uri.parse(url);
    final path = u.hasAuthority ? u.path : url;
    final rest = u.hasAuthority && u.hasQuery ? '?${u.query}' : '';
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return u.hasAuthority ? '$b$path$rest' : '$b$url';
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recording = false;
    level = 0;
    await platform.voiceStop();
  }

  String? _fail(String code, {String? message}) {
    _watchdog?.cancel();
    state = VoiceState.error;
    errorCode = code;
    errorMessage = message;
    level = 0;
    notifyListeners();
    unawaited(_stopRecording());
    _scheduleClose(const Duration(seconds: 6));
    return code;
  }

  void _finish() {
    _watchdog?.cancel();
    state = VoiceState.idle;
    level = 0;
    notifyListeners();
    _scheduleClose();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(silenceTimeout, () {
      if (active && state != VoiceState.speaking) {
        send({'type': 'voice', 'action': 'cancel', 'session': session});
        _fail('timeout');
      }
    });
  }

  void _scheduleClose([Duration? after]) {
    _dismiss?.cancel();
    _dismiss = Timer(after ?? dismissAfter, () {
      if (!active || state == VoiceState.error) _closeUi();
    });
  }

  void _closeUi() {
    unawaited(platform.closeUi('/voice'));
    if (state == VoiceState.error) {
      state = VoiceState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _watchdog?.cancel();
    super.dispose();
  }
}
