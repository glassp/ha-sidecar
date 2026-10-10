import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/kiosk_platform.dart';

enum VoiceState { idle, listening, thinking, speaking, error }

/// One exchange on the voice screen: what the user said and what the assistant answered (either may still be empty).
class VoiceTurn {
  VoiceTurn({this.user = '', this.assistant = ''});
  String user;
  String assistant;
}

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
    this.thinkTimeout = const Duration(seconds: 120),
    this.firstTimeout = const Duration(seconds: 12),
    this.conversationEnabled = _yes,
    this.followUpTimeout = _eight,
    this.soundsEnabled = _yes,
  });

  static bool _yes() => true;
  static Duration _eight() => const Duration(seconds: 8);

  final KioskPlatform platform;

  /// Sends one protocol message; false when there is no connection to Home Assistant.
  final bool Function(Map<String, dynamic> message) send;

  /// The address Home Assistant is reached at right now (answers are fetched from there), or null.
  final String? Function() baseUrl;
  final Duration dismissAfter;

  /// Safety net: a run that has not said anything for this long (Home Assistant stalled) is given up.
  final Duration silenceTimeout;

  /// The same, once the words are understood and the agent is working: a local LLM can take a minute to answer.
  final Duration thinkTimeout;

  /// How long the first listening waits for the user to start speaking (wake word or tap).
  final Duration firstTimeout;

  /// Settings, read when needed: keep listening after an answer, how long to wait for a follow-up, play the pings.
  final bool Function() conversationEnabled;
  final Duration Function() followUpTimeout;
  final bool Function() soundsEnabled;

  VoiceState state = VoiceState.idle;
  String? session;

  /// The conversation on screen; the last turn is the current one. A turn that Home Assistant wants continued
  /// (it asked something) is followed by another one without clearing the list.
  final List<VoiceTurn> turns = [];
  String get transcript => turns.isEmpty ? '' : turns.last.user;
  String get answer => turns.isEmpty ? '' : turns.last.assistant;

  /// The newest microphone levels (0..1), oldest first, for the live waveform.
  final List<double> levels = [];
  static const levelHistory = 32;
  bool _continue = false;

  /// A conversation runs from the first listening until nothing is said for a while, the user ends it or something fails.
  bool inConversation = false;

  /// The current listening is the one after an answer (the screen says so).
  bool followUp = false;

  /// Listening and nobody has started to speak yet; [speechDeadline] is when the conversation ends if it stays so.
  bool waitingForSpeech = false;
  DateTime? speechDeadline;
  Duration speechWindow = Duration.zero;
  bool _heardSpeech = false;
  bool _spokeAnswer = false;
  int _loudFrames = 0;
  Timer? _noSpeech;

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
  /// [wakeWord] is the phrase that started it (Home Assistant gets it with the run); [continuing] keeps the earlier turns on
  /// screen, [followUp] is the listening after an answer (it waits for the follow-up window instead of the first one).
  Future<String?> listen({
    String? wakeWord,
    bool continuing = false,
    bool followUp = false,
  }) async {
    if (active) await cancel(silent: true); // barge-in
    _dismiss?.cancel();
    _noSpeech?.cancel();
    final id = 'v${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    session = id;
    if (!continuing) turns.clear();
    turns.add(VoiceTurn());
    _continue = false;
    _heardSpeech = false;
    _spokeAnswer = false;
    _loudFrames = 0;
    inConversation = true;
    this.followUp = followUp;
    waitingForSpeech = false;
    errorCode = errorMessage = null;
    level = 0;
    levels.clear();
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
    // the ping comes first and the microphone opens after it, so the ping is not recorded
    if (soundsEnabled()) await platform.voicePing('start');
    if (session != id) return 'cancelled'; // ended while the ping played
    final err = await platform.voiceStart(id);
    if (err != null) {
      send({'type': 'voice', 'action': 'cancel', 'session': id});
      return _fail(err);
    }
    _recording = true;
    _armWatchdog();
    _armNoSpeech(id, followUp ? followUpTimeout() : firstTimeout);
    return null;
  }

  /// The user is done talking (button) or the recording hit its limit: Home Assistant gets the end of the audio.
  Future<void> stopListening() async {
    final id = session;
    if (id == null || !_recording) return;
    await _stopRecording();
    send({'type': 'voice', 'action': 'stop', 'session': id});
  }

  /// Aborts the turn (also stops the answer if it is being spoken). Does not end the conversation by itself.
  Future<void> cancel({bool silent = false}) async {
    final id = session;
    if (id != null) send({'type': 'voice', 'action': 'cancel', 'session': id});
    await _stopRecording();
    await platform.voiceStopPlayback();
    _watchdog?.cancel();
    _noSpeech?.cancel();
    waitingForSpeech = false;
    session = null;
    state = VoiceState.idle;
    level = 0;
    levels.clear();
    _continue = false;
    notifyListeners();
    if (!silent) _closeUi();
  }

  /// Ends the conversation: stops listening and speaking, plays the closing ping and closes the screen
  /// ([afterMs] later, so "Done" can be seen after a silence).
  Future<void> endConversation({
    int afterMs = 0,
    bool runIsOver = false,
  }) async {
    final was = inConversation;
    inConversation = false;
    followUp = false;
    if (runIsOver) {
      // Home Assistant finished the run itself: nothing to cancel there
      _watchdog?.cancel();
      _noSpeech?.cancel();
      waitingForSpeech = false;
      session = null;
      state = VoiceState.idle;
      level = 0;
      levels.clear();
      _continue = false;
      notifyListeners();
    } else {
      await cancel(silent: true);
    }
    if (was && soundsEnabled()) await platform.voicePing('end');
    if (afterMs > 0) {
      _scheduleClose(Duration(milliseconds: afterMs));
    } else {
      _closeUi();
    }
  }

  /// Announcement from Home Assistant: the pre-announce sound, then [url]; completes when it has been played.
  Future<void> announce({
    required String url,
    String message = '',
    String? preannounceUrl,
    bool keepOpen = false,
  }) async {
    if (active) await cancel(silent: true);
    _dismiss?.cancel();
    inConversation = false;
    session = null;
    turns
      ..clear()
      ..add(VoiceTurn(assistant: message));
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
      if (!keepOpen) _scheduleClose();
    }
  }

  /// Home Assistant starts a conversation (`start_conversation`, `ask_question`): the announcement is played, then the
  /// tablet listens for the answer by itself. Completes when the announcement has been played.
  Future<void> conversation({
    required String url,
    String message = '',
    String? preannounceUrl,
  }) async {
    await announce(
      url: url,
      message: message,
      preannounceUrl: preannounceUrl,
      keepOpen: true,
    );
    unawaited(listen(continuing: true, followUp: true));
  }

  /// The tablet lost Home Assistant: nobody will answer this turn.
  void onDisconnected() {
    if (active && session != null) {
      inConversation = false;
      unawaited(cancel());
    }
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
        levels.add(level);
        if (levels.length > levelHistory) levels.removeAt(0);
        // Home Assistant's own voice detection normally says when speech starts; this covers a pipeline that does not
        if (!_heardSpeech) {
          _loudFrames = level > 0.25 ? _loudFrames + 1 : 0;
          if (_loudFrames >= 3) _speechStarted();
        }
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
      case 'stt-vad-start':
        _speechStarted();
        notifyListeners();
      case 'stt-end':
        if (turns.isNotEmpty) turns.last.user = (data['text'] as String?) ?? '';
        _speechStarted();
        state = VoiceState.thinking;
        _armWatchdog(); // with the longer thinking limit
        unawaited(_stopRecording());
        send({'type': 'voice', 'action': 'stop', 'session': id});
        notifyListeners();
      case 'intent-end':
        if (turns.isNotEmpty) {
          turns.last.assistant = (data['text'] as String?) ?? '';
        }
        _continue = data['continue_conversation'] == true;
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
      _spokeAnswer = true;
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
    _noSpeech?.cancel();
    waitingForSpeech = false;
    inConversation = false;
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
    levels.clear();
    notifyListeners();
    final again = _continue || (_spokeAnswer && conversationEnabled());
    _continue = false;
    if (inConversation && again) {
      // keep the conversation going: listen for what comes next, the earlier turns stay on screen
      unawaited(listen(continuing: true, followUp: true));
      return;
    }
    if (inConversation && conversationEnabled()) {
      // an answer that was not spoken (a question to Home Assistant, no text): that was the conversation
      unawaited(endConversation(afterMs: 1200, runIsOver: true));
      return;
    }
    inConversation = false; // follow-ups are off: one question, one answer
    _scheduleClose();
  }

  /// Someone started talking: stop waiting for them to begin.
  void _speechStarted() {
    _heardSpeech = true;
    _noSpeech?.cancel();
    waitingForSpeech = false;
  }

  /// Ends the conversation if nobody says anything within [window] of listening starting.
  void _armNoSpeech(String id, Duration window) {
    _noSpeech?.cancel();
    waitingForSpeech = true;
    speechWindow = window;
    speechDeadline = DateTime.now().add(window);
    notifyListeners();
    _noSpeech = Timer(window, () {
      if (session == id && !_heardSpeech && state == VoiceState.listening) {
        unawaited(endConversation(afterMs: 1200));
      }
    });
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(state == VoiceState.thinking ? thinkTimeout : silenceTimeout, () {
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
    _noSpeech?.cancel();
    super.dispose();
  }
}
