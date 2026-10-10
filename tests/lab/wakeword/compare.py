"""Compares the Kotlin engine with reference.py chunk by chunk: kt.log holds the WWTEST lines of the app (see docs/TESTING.md)."""
import re, sys, subprocess, numpy as np
from reference import OWW, read
pairs=[("hey_jarvis","jarvis"),("hey_jarvis","jarvis2"),("hey_jarvis","alexa"),("hey_jarvis","neg1"),("hey_jarvis","neg2"),("alexa_v0.1","alexa"),("alexa_v0.1","jarvis"),("hey_mycroft_v0.1","mycroft"),("hey_mycroft_v0.1","neg2")]
log=open("kt.log").read()
kt={}
for m in re.finditer(r"(\w+)\.wav (\w+) max=([\d.]+) chunks=(\d+)\n.*?scores (.*)", log):
    kt[(m.group(2), m.group(1))]=[float(x.split(":")[1]) for x in m.group(5).split()]
worst=0
for word,f in pairs:
    wid=word.replace("_v0.1","") if word.startswith("hey_jarvis") is False else word
    key=("hey_jarvis" if word=="hey_jarvis" else word.replace("_v0.1",""), f)
    pcm=np.concatenate([np.zeros(16000,np.int16),read(f"audio/{f}.wav"),np.zeros(16000,np.int16)])
    o=OWW(".", "hey_jarvis_v0.1" if word=="hey_jarvis" else word)
    py=[]
    for k in range(0,len(pcm)-1279,1280): py.append(o.feed(pcm[k:k+1280])[0])
    k_=kt.get(key)
    if k_ is None: print("missing kotlin", key); continue
    n=min(len(py),len(k_)); d=max(abs(py[i]-k_[i]) for i in range(16,n))
    worst=max(worst,d)
    print(f"{key[0]:12s} {f:8s} chunks py={len(py)} kt={len(k_)}  max py={max(py):.4f} kt={max(k_):.4f}  max |diff| (chunks>=16) = {d:.5f}")
print("worst diff", worst)
