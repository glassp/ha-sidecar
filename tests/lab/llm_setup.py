"""Lab only: two floors, four rooms with a temperature sensor each, everything exposed to Assist, and the Lab pipeline switched
to the Ollama conversation agent.  python llm_setup.py <token-file>   (run with the Home Assistant venv's python)."""
import asyncio
import sys

import aiohttp

ROOMS = {
    "Ground floor": {"Kitchen": "sensor.kitchen_temperature", "Living room": "sensor.living_room_temperature"},
    "Upstairs": {"Bedroom": "sensor.bedroom_temperature", "Office": "sensor.office_temperature"},
}
AGENT = "conversation.lab_ollama"


async def main() -> None:
    token = open(sys.argv[1]).read().strip()
    async with aiohttp.ClientSession() as s, s.ws_connect("http://127.0.0.1:8123/api/websocket") as ws:
        await ws.receive_json()
        await ws.send_json({"type": "auth", "access_token": token})
        await ws.receive_json()
        n = 0

        async def call(**msg):
            nonlocal n
            n += 1
            await ws.send_json({"id": n, **msg})
            while True:
                r = await ws.receive_json()
                if r.get("id") == n:
                    return r

        existing_floors = {f["name"]: f["floor_id"] for f in (await call(type="config/floor_registry/list"))["result"]}
        existing_areas = {a["name"].lower(): a["area_id"] for a in (await call(type="config/area_registry/list"))["result"]}
        for floor, rooms in ROOMS.items():
            fid = existing_floors.get(floor) or (await call(type="config/floor_registry/create", name=floor))["result"]["floor_id"]
            for room, entity in rooms.items():
                aid = existing_areas.get(room.lower()) or (await call(type="config/area_registry/create", name=room, floor_id=fid))["result"]["area_id"]
                await call(type="config/area_registry/update", area_id=aid, floor_id=fid)
                r = await call(type="config/entity_registry/update", entity_id=entity, area_id=aid)
                print(entity, "->", room, floor, "ok" if r.get("success") else r)
                await call(type="homeassistant/expose_entity", assistants=["conversation"], entity_ids=[entity], should_expose=True)
        pipes = (await call(type="assist_pipeline/pipeline/list"))["result"]
        lab = next(p for p in pipes["pipelines"] if p["name"].lower().startswith("lab"))
        lab.pop("id")
        lab["conversation_engine"] = AGENT
        lab["conversation_language"] = "en"
        r = await call(type="assist_pipeline/pipeline/update", pipeline_id=pipes["preferred_pipeline"], **lab)
        print("pipeline:", r.get("success"), r.get("error"))


asyncio.run(main())
