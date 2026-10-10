"""Python reference of the openWakeWord streaming pipeline, used to check the Kotlin engine (docs/TESTING.md).

Setup (a scratch directory, nothing here is shipped): a venv with `ai-edge-litert` and `numpy`, the tflite models of
openWakeWord v0.5.1 next to this file (melspectrogram, embedding_model, hey_jarvis_v0.1, alexa_v0.1, hey_mycroft_v0.1) and 16 kHz mono wavs,
for example `say -v Samantha -o a.aiff "Hey Jarvis"; afconvert -f WAVE -d LEI16@16000 -c 1 a.aiff a.wav`.
Run: python reference.py hey_jarvis_v0.1 a.wav   (prints the best score; the Kotlin side logs the same under the tag WWTEST)
"""
import sys, wave, numpy as np
from ai_edge_litert.interpreter import Interpreter

class OWW:
    """Reference of the openWakeWord streaming pipeline (mel -> embedding -> classifier), written from its documented behaviour."""
    def __init__(self, d, word):
        self.mel = Interpreter(model_path=f"{d}/melspectrogram.tflite")
        self.emb = Interpreter(model_path=f"{d}/embedding_model.tflite"); self.emb.allocate_tensors()
        self.clf = Interpreter(model_path=f"{d}/{word}.tflite"); self.clf.allocate_tensors()
        self.raw = np.zeros(0, np.float32)
        self.mels = np.ones((76, 32), np.float32)
        self.feats = None
        self.n = 0
    def _mel(self, samples):
        i = self.mel.get_input_details()[0]
        self.mel.resize_tensor_input(i["index"], [1, len(samples)]); self.mel.allocate_tensors()
        self.mel.set_tensor(i["index"], samples[None, :].astype(np.float32)); self.mel.invoke()
        out = self.mel.get_tensor(self.mel.get_output_details()[0]["index"])
        return np.squeeze(out, (0, 1)) / 10.0 + 2.0   # (frames, 32)
    def _embed(self, window):
        i = self.emb.get_input_details()[0]
        self.emb.set_tensor(i["index"], window[None, :, :, None].astype(np.float32)); self.emb.invoke()
        return self.emb.get_tensor(self.emb.get_output_details()[0]["index"]).reshape(96)
    def feed(self, chunk):  # exactly 1280 int16 samples
        self.raw = np.concatenate([self.raw, chunk.astype(np.float32)])
        ctx = self.raw[-(1280 + 160 * 3):]
        m = self._mel(ctx)
        self.mels = np.vstack([self.mels, m])[-976:]
        e = self._embed(self.mels[-76:])
        if self.feats is None: self.feats = np.tile(e, (16, 1))
        self.feats = np.vstack([self.feats, e])[-120:]
        self.n += 1
        i = self.clf.get_input_details()[0]
        self.clf.set_tensor(i["index"], self.feats[-16:][None].astype(np.float32)); self.clf.invoke()
        s = float(self.clf.get_tensor(self.clf.get_output_details()[0]["index"]).reshape(-1)[0])
        return 0.0 if self.n < 5 else s, m.shape[0]

def read(path):
    with wave.open(path) as w: assert w.getframerate() == 16000 and w.getnchannels() == 1
    with wave.open(path) as w: return np.frombuffer(w.readframes(w.getnframes()), np.int16)

if __name__ == "__main__":
    word = sys.argv[1]
    for path in sys.argv[2:]:
        pcm = np.concatenate([np.zeros(16000, np.int16), read(path), np.zeros(16000, np.int16)])
        o = OWW(".", word); best = 0; frames = set()
        for k in range(0, len(pcm) - 1279, 1280):
            s, f = o.feed(pcm[k:k + 1280]); best = max(best, s); frames.add(f)
        print(f"{word:18s} {path:22s} max score {best:.3f}  mel frames/chunk {sorted(frames)}")
