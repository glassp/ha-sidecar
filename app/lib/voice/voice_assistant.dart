/// Voice interfaces. Not implemented yet - see docs/ROADMAP.md (phase 3).
///
/// Plan: the integration exposes this device as an `assist_satellite` entity; audio is
/// streamed over the existing sidecar WebSocket (or HA's Assist pipeline WebSocket API),
/// wake word runs on-device (openWakeWord/TFLite) behind [WakeWordEngine].
library;

class WakeWordDetection {
  const WakeWordDetection(this.phrase, this.confidence);
  final String phrase;
  final double confidence;
}

abstract class WakeWordEngine {
  Stream<WakeWordDetection> get detections;
  Future<void> start();
  Future<void> stop();
}

enum VoiceState { idle, listening, thinking, speaking }

abstract class VoiceAssistant {
  Stream<VoiceState> get state;

  /// Push-to-talk or wake-word triggered conversation with the configured Assist pipeline.
  Future<void> startConversation({String? pipelineId});
  Future<void> cancel();

  /// Plays a TTS announcement pushed from HA (assist_satellite.announce).
  Future<void> announce(Uri audioUrl);
}
