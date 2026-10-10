// Runs the timers card against a tiny DOM stub: node --test tests/js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../../custom_components/ha_sidecar/www/ha-sidecar-timers-card.js", import.meta.url), "utf8");

function load() {
  const defined = {};
  const builds = { n: 0 };
  class FakeElement {
    constructor() {
      let html = "";
      this.shadowRoot = {
        get innerHTML() { return html; },
        set innerHTML(v) { html = v; builds.n += 1; },
        querySelectorAll: () => [],
      };
    }
    attachShadow() { return this.shadowRoot; }
    dispatchEvent() {}
  }
  const sandbox = {
    HTMLElement: FakeElement,
    customElements: { define: (n, c) => { defined[n] = c; } },
    window: { customCards: [] },
    document: { createElement: () => new FakeElement() },
    setInterval: () => 1,
    clearInterval: () => {},
    setTimeout,
    Promise, Error, Date, Math, Number, String, JSON, Array, CustomEvent: class {},
  };
  vm.runInNewContext(source, sandbox);
  return { defined, sandbox, builds };
}

const NOW = Date.parse("2026-10-10T12:00:00Z");
const iso = (ms) => new Date(ms).toISOString();

const timers = {
  running: { timer_id: "t1", label: "pasta", kind: "countdown", state: "running", duration: 600, remaining: 600, elapsed: 0, ends_at: iso(NOW + 100_000), started_at: iso(NOW - 500_000) },
  paused: { timer_id: "t2", label: "tea", kind: "countdown", state: "paused", duration: 180, remaining: 108, elapsed: 72, ends_at: null, started_at: null },
  finished: { timer_id: "t3", label: "", kind: "countdown", state: "finished", duration: 60, remaining: 0, elapsed: 60, ends_at: null, started_at: null, finished_at: iso(NOW - 3000) },
  stopwatch: { timer_id: "t4", label: "bread", kind: "countup", state: "running", duration: 0, remaining: 0, elapsed: 5, ends_at: null, started_at: iso(NOW - 65_000) },
};

function card(env, config, list, extra = {}) {
  const el = new env.defined["ha-sidecar-timers-card"]();
  el.setConfig(config);
  el.hass = {
    states: { "sensor.wallpanel_timers": { attributes: { timers: list } } },
    entities: { "sensor.wallpanel_timers": { device_id: "dev1" } },
    callService: async () => {},
    callWS: async () => [],
    ...extra,
  };
  return el;
}

test("registers itself as a custom card", () => {
  const env = load();
  assert.equal(env.sandbox.window.customCards[0].type, "ha-sidecar-timers-card");
});

test("a card without a tablet is rejected", () => {
  const env = load();
  assert.throws(() => new env.defined["ha-sidecar-timers-card"]().setConfig({}), /Choose a tablet/);
});

test("one tile per timer, with its label and the right buttons", () => {
  const env = load();
  const html = card(env, { tablet: "wallpanel" }, Object.values(timers)).shadowRoot.innerHTML;
  assert.equal((html.match(/class="tile/g) || []).length, 4);
  assert.match(html, /pasta/);
  assert.match(html, /bread/);
  assert.match(html, /data-act="pause_timer"/); // the running ones
  assert.match(html, /data-act="resume_timer"/); // the paused one
  assert.equal((html.match(/data-act="plus"/g) || []).length, 3, "no +1 min for the stopwatch");
  assert.match(html, /title="Dismiss"/); // the finished one
});

test("nothing is shown while there is no timer (unless asked)", () => {
  const env = load();
  assert.match(card(env, { tablet: "wallpanel" }, []).shadowRoot.innerHTML, /ha-card \{ display: none/);
  assert.match(card(env, { tablet: "wallpanel", hide_when_empty: false }, []).shadowRoot.innerHTML, /ha-card \{ display: block/);
});

test("an unknown tablet is explained, not hidden", () => {
  const env = load();
  const el = new env.defined["ha-sidecar-timers-card"]();
  el.setConfig({ tablet: "nope" });
  el.hass = { states: {}, entities: {}, callService: async () => {}, callWS: async () => [] };
  assert.match(el.shadowRoot.innerHTML, /Unknown tablet "nope"/);
});

test("running countdown shows what is left by its end time; paused keeps its value; finished counts up; stopwatch counts up", () => {
  const env = load();
  const el = card(env, { tablet: "wallpanel" }, []);
  assert.equal(Math.round(el._values(timers.running, NOW).seconds), 100);
  assert.equal(Math.round(el._values(timers.running, NOW + 40_000).seconds), 60);
  assert.equal(el._values(timers.paused, NOW + 999_000).seconds, 108);
  const done = el._values(timers.finished, NOW);
  assert.equal(done.over, true);
  assert.equal(Math.round(done.seconds), 3);
  assert.equal(Math.round(el._values(timers.stopwatch, NOW).seconds), 65);
  assert.ok(el._values(timers.running, NOW).fraction > 0.1 && el._values(timers.running, NOW).fraction < 0.2);
});

test("a second of ticking does not rebuild the tiles (a press must not land on a replaced button)", () => {
  const env = load();
  const el = card(env, { tablet: "wallpanel" }, Object.values(timers));
  const builds = env.builds.n;
  el.hass = { ...el._hass }; // Home Assistant sets hass on every state change anywhere
  el._refresh();
  assert.equal(env.builds.n, builds);
  // but a change of a timer does
  el.hass = { ...el._hass, states: { "sensor.wallpanel_timers": { attributes: { timers: [timers.running] } } } };
  assert.ok(env.builds.n > builds);
});

test("buttons call the tablet's timer services with the device and the timer", async () => {
  const env = load();
  const calls = [];
  const el = card(env, { tablet: "wallpanel" }, Object.values(timers), { callService: async (d, s, data) => calls.push([d, s, data]) });
  await el._act("pause_timer", timers.running);
  await el._act("adjust_timer", timers.running, { seconds: 60 });
  assert.equal(JSON.stringify(calls[0]), JSON.stringify(["ha_sidecar", "pause_timer", { device_id: "dev1", timer_id: "t1" }]));
  assert.equal(JSON.stringify(calls[1]), JSON.stringify(["ha_sidecar", "adjust_timer", { device_id: "dev1", timer_id: "t1", seconds: 60 }]));
});

test("without the entity registry the device comes from the tablet list", async () => {
  const env = load();
  const calls = [];
  const el = card(env, { tablet: "wallpanel" }, Object.values(timers), {
    entities: {},
    callWS: async () => [{ prefix: "wallpanel", name: "Wall", device_id: "dev9" }],
    callService: async (d, s, data) => calls.push(data),
  });
  await el._act("cancel_timer", timers.paused);
  assert.equal(calls[0].device_id, "dev9");
});
