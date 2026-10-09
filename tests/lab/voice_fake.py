"""A fake tablet speaking the sidecar voice protocol, against the lab Home Assistant (docs/VOICE.md, docs/TESTING.md).

Needs, in the lab Home Assistant: the integration paired as entity prefix `lab`, the `lab_voice` component (tests/lab/lab_voice)
set up and a pipeline using its STT/TTS as the preferred one, and the real tablet offline (it would take the connection back).
Environment: HA_URL (default http://127.0.0.1:8123), HA_API_TOKEN_FILE (a long-lived token, used for the REST/WebSocket API),
HA_STORAGE (the `.storage` directory, to read the tablet's token from the config entry).
Run with the Python of the Home Assistant venv: python3 tests/lab/voice_fake.py
"""
import os
import urllib.parse, asyncio, base64, json, math, struct, sys, time, aiohttp
B=os.environ.get("HA_URL","http://127.0.0.1:8123"); tok=open(os.environ["HA_API_TOKEN_FILE"]).read().strip(); H={"Authorization":"Bearer "+tok}
ENT="assist_satellite.lab_assist"; results=[]
def check(name, ok, detail=""):
    results.append(ok); print(("PASS " if ok else "FAIL ")+name, detail, flush=True)

def local(url):
    p=urllib.parse.urlparse(url); return B+p.path+(('?'+p.query) if p.query else '')

def device_token():
    entries=json.load(open(os.path.join(os.environ["HA_STORAGE"],"core.config_entries")))["data"]["entries"]
    return [e for e in entries if e["domain"]=="ha_sidecar"][0]["data"]["token"]

def pcm(seconds=1.0, hz=300):
    n=int(16000*seconds); return b"".join(struct.pack("<h",int(6000*math.sin(2*math.pi*hz*i/16000))) for i in range(n))

class Tablet:
    def __init__(self, s): self.s=s; self.events=[]; self.cmds=[]; self.ws=None
    async def connect(self):
        self.ws=await self.s.ws_connect(B+"/api/ha_sidecar/ws")
        await self.ws.send_json({"type":"hello","protocol":1,"token":device_token(),"device":{"model":"fake"}})
        m=await self.ws.receive_json(timeout=10); assert m["type"]=="hello_ok", m
        self.reader=asyncio.create_task(self._read())
    async def _read(self):
        try:
            async for raw in self.ws:
                if raw.type!=aiohttp.WSMsgType.TEXT: continue
                m=raw.json()
                if m["type"]=="voice_event": self.events.append((m["session"],m["event"],m["data"]))
                elif m["type"]=="command": self.cmds.append(m); asyncio.create_task(self._answer(m))
        except Exception as e: print("reader ended", e)
    async def _answer(self, m):
        if m["command"]=="voice_announce":
            await asyncio.sleep(0.5)
            await self.ws.send_json({"type":"result","id":m["id"],"success":True,"data":{}})
        else:
            await self.ws.send_json({"type":"result","id":m["id"],"success":True,"data":{}})
    async def v(self, action, session, **kw): await self.ws.send_json({"type":"voice","action":action,"session":session,**kw})
    async def speak(self, session, seconds=1.0, **kw):
        await self.v("start",session,**kw)
        data=pcm(seconds)
        for i in range(0,len(data),3200):
            await self.v("audio",session,data=base64.b64encode(data[i:i+3200]).decode()); await asyncio.sleep(0.02)
        await self.v("stop",session)
    def kinds(self, session): return [e for s,e,_ in self.events if s==session]
    async def wait_for(self, session, kind, t=15):
        end=time.time()+t
        while time.time()<end:
            if kind in self.kinds(session): return True
            await asyncio.sleep(0.1)
        return False

async def main():
    async with aiohttp.ClientSession(headers=H) as s:
        states=[]
        async def watch():
            async with s.ws_connect(B+"/api/websocket") as ws:
                await ws.receive_json(); await ws.send_json({"type":"auth","access_token":tok}); await ws.receive_json()
                await ws.send_json({"id":1,"type":"subscribe_events","event_type":"state_changed"}); await ws.receive_json()
                async for raw in ws:
                    if raw.type!=aiohttp.WSMsgType.TEXT: continue
                    m=raw.json()
                    if m.get("type")=="event" and m["event"]["data"]["entity_id"]==ENT:
                        ns=m["event"]["data"]["new_state"]; states.append(ns["state"] if ns else None)
        asyncio.create_task(watch())
        async def state(): return (await (await s.get(f"{B}/api/states/{ENT}")).json())["state"]
        t=Tablet(s); await t.connect(); await asyncio.sleep(2)
        check("entity becomes idle when the tablet connects", await state()=="idle", await state())

        # 1. a full push-to-talk turn
        states.clear(); await t.speak("s1")
        ok=await t.wait_for("s1","run-end"); k=t.kinds("s1")
        print("   events:", k)
        check("turn ends with run-end", ok)
        for need in ("stt-start","stt-end","intent-end","tts-end"): check(f"turn has {need}", need in k)
        d={e:x for s_,e,x in t.events if s_=="s1"}
        check("stt text delivered", d.get("stt-end",{}).get("text")=="what time is it", str(d.get("stt-end")))
        check("answer text delivered", bool(d.get("intent-end",{}).get("text")), str(d.get("intent-end")))
        url=d.get("tts-end",{}).get("url","")
        r=await s.get(local(url)); body=await r.read()
        check("tts url playable", r.status==200 and len(body)>1000, f"{r.status} {len(body)} bytes {r.headers.get('content-type')} url={url[:60]}")
        check("state while the answer is spoken is responding", "responding" in states, str(states))
        await t.v("played","s1"); await asyncio.sleep(1)
        check("played returns the entity to idle", await state()=="idle", f"{await state()} {states}")
        check("state sequence", states[:1]==["listening"] and "processing" in states and states[-1]=="idle", str(states))

        # 2. announcement (blocks until the tablet answers)
        await t.ws.send_json({"type":"event","event":"noop","data":{}})
        t0=time.time()
        r=await s.post(f"{B}/api/services/assist_satellite/announce",json={"entity_id":ENT,"message":"Dinner is ready","preannounce":True})
        dt=time.time()-t0
        ann=[c for c in t.cmds if c["command"]=="voice_announce"]
        check("announce reaches the tablet", r.status==200 and len(ann)==1, f"{r.status} cmds={len(ann)}")
        if ann:
            a=ann[0]["data"]; print("   announce data:", {k:(v[:60] if isinstance(v,str) else v) for k,v in a.items()})
            check("announce carries url, message and preannounce", bool(a.get("url")) and a.get("message")=="Dinner is ready" and "preannounce_url" in a)
            ra=await s.get(local(a["url"])); check("announce url playable", ra.status==200, str(ra.status))
        check("announce blocks until the tablet finished (>=0.5s)", dt>=0.5, f"{dt:.2f}s")
        await asyncio.sleep(0.5); check("entity idle after announce", await state()=="idle", await state())

        # 3. barge-in: a new start interrupts the running turn
        await t.v("start","b1"); await t.v("audio","b1",data=base64.b64encode(pcm(0.1)).decode())
        await asyncio.sleep(0.3); await t.speak("b2"); ok=await t.wait_for("b2","run-end")
        k2=t.kinds("b2"); print("   b2:", k2, " b1:", t.kinds("b1"))
        check("barge-in: the second turn completes", ok and "tts-end" in k2, str(k2))
        check("barge-in: no event of the cancelled run leaks into the new turn", k2[:1]==["run-start"] and k2.count("run-end")==1 and k2.index("run-end")>k2.index("tts-end"), str(k2))
        check("barge-in: the first turn did not complete", "tts-end" not in t.kinds("b1"), str(t.kinds("b1")))
        await t.v("played","b2"); await asyncio.sleep(0.5)

        # 4. cancel
        n0=len(t.events); await t.v("start","c1"); await asyncio.sleep(0.5); await t.v("cancel","c1"); await asyncio.sleep(1.5)
        check("cancel returns the entity to idle", await state()=="idle", await state())

        # 5. garbage never breaks it
        await t.v("audio","nope",data="!!!"); await t.v("start","g1"); await t.v("audio","g1",data="not-base64!"); await t.v("audio","g1",data=base64.b64encode(b"\x01").decode())
        await t.ws.send_json({"type":"voice"}); await t.ws.send_json({"type":"voice","action":"start"}); await t.v("stop","g1"); await asyncio.sleep(2)
        check("garbage input: still alive", await state() in ("idle","listening","processing"), await state())
        await t.v("cancel","g1"); await asyncio.sleep(1)
        await t.speak("after"); check("a turn after garbage works", await t.wait_for("after","run-end"))
        await t.v("played","after")

        # 6. disconnect mid-turn
        await t.v("start","d1"); await asyncio.sleep(0.3); await t.ws.close(); await asyncio.sleep(2)
        check("disconnect makes the entity unavailable", await state()=="unavailable", await state())
        t2=Tablet(s); await t2.connect(); await asyncio.sleep(2)
        check("reconnect: idle again, no stuck session", await state()=="idle", await state())
        await t2.speak("again"); check("a turn after reconnect works", await t2.wait_for("again","run-end"))
        print(f"\n{sum(results)}/{len(results)} passed"); sys.exit(0 if all(results) else 1)
asyncio.run(main())
