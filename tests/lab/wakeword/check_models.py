"""Vets catalogue models: every classifier must take [1,16,96] and return [1,1], must react to its own phrase (macOS `say` speech,
two voices) and the matrix shows cross activations. Needs reference.py, the shared models and one <name>.tflite per phrase next to it,
and audio2/<name>_<Voice>.wav (docs/TESTING.md)."""
import sys, glob, numpy as np
from reference import OWW, read
from ai_edge_litert.interpreter import Interpreter
names = sorted(set(p.split("/")[-1].rsplit("_",1)[0] for p in glob.glob("audio2/*.wav")))
print("shapes:")
for n in names:
    it = Interpreter(model_path=f"{n}.tflite"); i = it.get_input_details()[0]["shape"].tolist(); o = it.get_output_details()[0]["shape"].tolist()
    if i != [1,16,96] or o != [1,1]: print("  ODD", n, i, o)
print("score matrix: rows = spoken phrase (best over 2 voices), columns = model; own model in [ ]")
def best(model, wav):
    pcm = np.concatenate([np.zeros(16000,np.int16), read(wav), np.zeros(16000,np.int16)])
    o = OWW(".", model); b = 0
    for k in range(0, len(pcm)-1279, 1280): b = max(b, o.feed(pcm[k:k+1280])[0])
    return b
own_fail=[]; cross=[]
for spoken in names:
    row=[]
    for model in names:
        s = max(best(model, f"audio2/{spoken}_{v}.wav") for v in ("Samantha","Daniel"))
        row.append(s)
        if model==spoken and s<0.5: own_fail.append((spoken,s))
        if model!=spoken and s>=0.5: cross.append((spoken,model,s))
    print(f"{spoken:15s} own={row[names.index(spoken)]:.3f}")
print("own score < 0.5:", own_fail)
print("cross activations >= 0.5:", cross)
