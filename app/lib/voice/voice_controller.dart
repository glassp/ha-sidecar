import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/kiosk_platform.dart';
import 'voice_card.dart';
import 'voice_skin.dart';

enum VoiceState { idle, listening, thinking, speaking, error }

/// One exchange on the voice screen: what the user said and what the assistant answered (either may still be empty).
class VoiceTurn {
  VoiceTurn({
    this.user = '',
    this.assistant = '',
    this.session,
    List<VoiceCard>? cards,
  }) : cards = cards ?? [];
  String user;
  String assistant;

  /// The run this turn belongs to (a card for it can arrive after the next listening has started).
  final String? session;

  /// Result cards for the answer (weather, what was switched, ...).
  final List<VoiceCard> cards;
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
    this.dockedEnabled = _no,
    this.volumeLevel = _noVolume,
    this.saveVolume = _noSave,
    this.skinId = _defaultSkin,
    this.bubbleText = _identity,
  });

  static bool _yes() => true;
  static bool _no() => false;
  static int? _noVolume() => null;
  static String _defaultSkin() => VoiceSkin.defaultId;
  static Future<void> _noSave(int percent) async {}
  static String _identity(String key) => key;
  static Duration _eight() => const Duration(seconds: 8);

  final KioskPlatform platform;

  /// Sends one protocol message; false when there is no connection to Home Assistant.
  final bool Function(Map<String, dynamic> message) send;

  /// The address Home Assistant is reached at right now (answers are fetched from there), or null.
  final String? Function() baseUrl;
  final Duration dismissAfter;

  /// Whether the voice screen may be shown as a small card over whatever is in front (it still needs the permission).
  final bool Function() dockedEnabled;

  /// The media volume (%) during a voice session, or null to leave the volume alone. The level from before comes back afterwards.
  final int? Function() volumeLevel;

  /// Persists the preferred voice volume (a volume command outside a conversation).
  final Future<void> Function(int percent) saveVolume;

  /// The id of the skin (look) of the docked card.
  final String Function() skinId;

  /// Localized text for the docked card (a key of the `voice.*` translations).
  final String Function(String key) bubbleText;

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

  /// The voice screen is open (as the full page or as the docked card).
  bool shown = false;

  /// The voice screen is the docked card; the user can expand it to the full page ([expanded] then stays until it closes).
  bool docked = false;
  bool expanded = false;
  String _lastBubbleSignature = '';
  bool _volumeRaised = false;
  Timer? _volumeTimer;
  int? _volumeOverride;
  final Stopwatch _sinceBubble = Stopwatch()..start();

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
    turns.add(VoiceTurn(session: id));
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
    await _open();
    await _raiseVolume();
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
    if (!silent) {
      // the screen closes with it, so nothing is left to follow up: the conversation is over (otherwise the raised volume
      // would never be given back, and the next turn would count as a follow-up)
      inConversation = false;
      _closeUi();
    }
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
    await _open();
    await _raiseVolume();
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
    if (msg['event'] == 'cards') {
      // cards belong to a turn that may already be followed by the next listening (a new session)
      final turn = turns.where((t) => t.session == id).firstOrNull;
      final data = (msg['data'] as Map?) ?? const {};
      if (turn == null) return;
      turn.cards.addAll(_parseCards(data['cards']));
      notifyListeners();
      return;
    }
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

  List<VoiceCard> _parseCards(Object? raw) => [
    for (final c in (raw as List? ?? const []))
      ?VoiceCard.fromJson(c, url: _cardUrl),
  ];

  /// A path on Home Assistant is fetched through the address we are connected through; any other URL stays as it is.
  String? _cardUrl(String url) => url.startsWith('/') ? _absolute(url) : url;

  /// Cards to show from Home Assistant (`show_card`): during a conversation they join the answer; otherwise they appear
  /// on their own for [seconds].
  Future<void> showCards(List<dynamic> raw, {int seconds = 20}) async {
    final cards = _parseCards(raw);
    if (cards.isEmpty) return;
    if (turns.isNotEmpty && (active || inConversation)) {
      turns.last.cards.addAll(cards);
      notifyListeners();
      return;
    }
    _dismiss?.cancel();
    turns
      ..clear()
      ..add(VoiceTurn(cards: cards));
    errorCode = errorMessage = null;
    state = VoiceState.idle;
    notifyListeners();
    await _open();
    notifyListeners();
    _scheduleClose(Duration(seconds: seconds));
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
    _restoreVolumeWhenDone();
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
    _watchdog = Timer(
      state == VoiceState.thinking ? thinkTimeout : silenceTimeout,
      () {
        if (active && state != VoiceState.speaking) {
          send({'type': 'voice', 'action': 'cancel', 'session': session});
          _fail('timeout');
        }
      },
    );
  }

  void _scheduleClose([Duration? after]) {
    _dismiss?.cancel();
    _dismiss = Timer(after ?? dismissAfter, () {
      if (!active || state == VoiceState.error) _closeUi();
    });
  }

  /// Opens the voice screen: the docked card when it is on and possible, otherwise the full page.
  Future<void> _open() async {
    shown = true;
    // the card is already up from an earlier turn of this conversation
    if (docked) return;
    if (!expanded && dockedEnabled() && await platform.bubbleAvailable()) {
      docked = true;
      _pushBubble(force: true);
    } else {
      unawaited(platform.showUi('/voice'));
    }
  }

  /// The user tapped the card: continue on the full page.
  Future<void> expand() async {
    if (!docked) return;
    docked = false;
    expanded = true;
    unawaited(platform.bubbleHide());
    unawaited(platform.showUi('/voice'));
    notifyListeners();
  }

  /// A button on the docked card (`bubble_action` event from the platform).
  Future<void> onBubbleAction(String action) async {
    switch (action) {
      case 'done':
        await stopListening();
      case 'end' || 'close':
        await endConversation();
      case 'again':
        await listen();
      case 'expand':
        await expand();
      case String a when a.startsWith('volume:'):
        await changeVolume(int.tryParse(a.substring(7)) ?? 50);
    }
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (docked) _pushBubble();
    _restoreVolumeWhenDone();
  }

  /// Voice answers are played at the voice volume; the level from before is restored a moment after the session is over
  /// (not between two turns of a conversation: the volume does not jump up and down).
  /// The voice volume (%) shown next to the answer, or null if the volume is not managed.
  int? get volume => _volumeOverride ?? volumeLevel();

  /// The slider on the screen / card: applies at once, also while an answer is playing, and only for this session. The voice
  /// volume setting is not changed: the next conversation starts at the configured level again.
  Future<void> changeVolume(int percent) async {
    _volumeOverride = percent.clamp(0, 100);
    notifyListeners();
    if (_volumeRaised) await platform.voiceVolumeRaise(_volumeOverride!);
  }

  /// "Set the volume to 30 percent" / "louder" (from Home Assistant): during a conversation it applies to that conversation
  /// only; otherwise it sets the preferred voice volume. Returns which of the two it was.
  Future<String> setVolumeCommand({int? percent, int? delta}) async {
    final p = (percent ?? (volume ?? 50) + (delta ?? 0)).clamp(0, 100);
    if (active || inConversation || _volumeRaised) {
      await changeVolume(p);
      return 'conversation';
    }
    await saveVolume(p);
    return 'preferred';
  }

  Future<void> _raiseVolume() async {
    _volumeTimer?.cancel();
    final level = volume;
    if (level == null) return;
    _volumeRaised = true;
    await platform.voiceVolumeRaise(level);
  }

  void _restoreVolumeWhenDone() {
    if (!_volumeRaised || active || inConversation) return;
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 800), () {
      if (active || inConversation || !_volumeRaised) return;
      _volumeRaised = false;
      _volumeOverride = null; // the slider was for this conversation only
      unawaited(platform.voiceVolumeRestore());
    });
  }

  String _bubbleError() {
    final key = 'err_${(errorCode ?? 'unknown').replaceAll('-', '_')}';
    final t = bubbleText(key);
    return t == key || t.endsWith(key) ? bubbleText('err_unknown') : t;
  }

  /// The turn the docked card shows: the current one, except while waiting for a follow-up that has not started yet, when the
  /// last answer (and its cards) stays on the card until you speak.
  VoiceTurn? get _shownTurn {
    if (turns.isEmpty) return null;
    final last = turns.last;
    final blank =
        last.user.isEmpty && last.assistant.isEmpty && last.cards.isEmpty;
    return state == VoiceState.listening && blank && turns.length > 1
        ? turns[turns.length - 2]
        : last;
  }

  void _pushBubble({bool force = false}) {
    final shown = _shownTurn;
    final deadline = waitingForSpeech
        ? speechDeadline?.millisecondsSinceEpoch ?? 0
        : 0;
    final fixed = {
      'state': state.name,
      'follow_up': followUp,
      'user': shown?.user ?? '',
      'assistant': shown?.assistant ?? '',
      'error': state == VoiceState.error ? _bubbleError() : '',
      'in_conversation': inConversation,
      'volume': volume ?? -1,
      'cards': [
        for (final c in shown?.cards ?? const <VoiceCard>[]) c.toSnapshot(),
      ],
      'skin': VoiceSkin.byId(skinId()).toSnapshot(),
      'wait_deadline_ms': deadline,
      'wait_total_ms': speechWindow.inMilliseconds,
      'labels': {
        'listening': bubbleText('listening'),
        'follow_up': bubbleText('listening_followup'),
        'thinking': bubbleText('thinking'),
        'speaking': bubbleText('speaking'),
        'idle': bubbleText('done'),
        'error': bubbleText('error_chip'),
        'done': bubbleText('done_talking'),
        'end': bubbleText('end_conversation'),
        'again': bubbleText('talk_again'),
      },
    };
    final signature = fixed.toString();
    // microphone levels arrive about ten times a second: send them, but not faster than the card can use
    if (!force &&
        signature == _lastBubbleSignature &&
        _sinceBubble.elapsedMilliseconds < 90) {
      return;
    }
    _lastBubbleSignature = signature;
    _sinceBubble.reset();
    unawaited(platform.bubbleUpdate({...fixed, 'level': level}));
  }

  void _closeUi() {
    if (docked) {
      unawaited(platform.bubbleHide());
    } else {
      unawaited(platform.closeUi('/voice'));
    }
    docked = false;
    expanded = false;
    shown = false;
    _restoreVolumeWhenDone();
    if (state == VoiceState.error) {
      state = VoiceState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    _dismiss?.cancel();
    _watchdog?.cancel();
    _noSpeech?.cancel();
    super.dispose();
  }
}
