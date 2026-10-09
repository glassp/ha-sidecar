// Runs the beacon card against a tiny DOM stub: node --test tests/js
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../../custom_components/ha_sidecar/www/ha-sidecar-beacon-card.js", import.meta.url), "utf8");

function load() {
  const timers = [];
  const defined = {};
  let now = 0;
  const visible = { state: "visible" };
  class FakeElement {
    constructor() { this.shadowRoot = { innerHTML: "" }; this.isConnected = false; }
    attachShadow() { return this.shadowRoot; }
    dispatchEvent() {}
  }
  const sandbox = {
    HTMLElement: FakeElement,
    customElements: { define: (n, c) => { defined[n] = c; } },
    window: {
      customCards: [],
      location: { pathname: "/lovelace/wall" },
      listeners: {},
      addEventListener(name, fn) { (this.listeners[name] = this.listeners[name] || []).push(fn); },
      removeEventListener(name, fn) { this.listeners[name] = (this.listeners[name] || []).filter((f) => f !== fn); },
    },
    document: { createElement: () => new FakeElement(), get visibilityState() { return visible.state; } },
    performance: { now: () => now },
    requestAnimationFrame: () => 1,
    cancelAnimationFrame: () => {},
    setInterval: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearInterval: () => {},
    setTimeout: (fn, ms) => setTimeout(fn, ms).unref(),
    Promise, Error, Date, Math, Number, String, CustomEvent: class {},
  };
  vm.runInNewContext(source, sandbox);
  return { defined, timers, sandbox, visible, advance: (ms) => { now += ms; } };
}

function card(env, config, callWS) {
  const el = new env.defined["ha-sidecar-beacon-card"]();
  el.setConfig(config);
  el.hass = { callWS };
  el.isConnected = true;
  el.connectedCallback();
  return el;
}

test("registers itself as a custom card", () => {
  const env = load();
  assert.equal(env.sandbox.window.customCards[0].type, "ha-sidecar-beacon-card");
});

test("a card without a tablet is rejected", () => {
  const env = load();
  const el = new env.defined["ha-sidecar-beacon-card"]();
  assert.throws(() => el.setConfig({ type: "custom:ha-sidecar-beacon-card" }), /Choose a tablet/);
});

test("pings immediately and then on the interval", async () => {
  const env = load();
  const calls = [];
  const el = card(env, { tablet: "wallpanel", interval: 30 }, async (msg) => { calls.push(msg); return { ok: true }; });
  await new Promise((r) => setImmediate(r));
  assert.equal(JSON.stringify(calls[0]), JSON.stringify({ type: "ha_sidecar/beacon", tablet: "wallpanel", state: "active", path: "/lovelace/wall" }));
  assert.equal(env.timers[0].ms, 30000);
  await el._ping();
  assert.equal(calls.length, 2); // one from start, one from the explicit call
  assert.match(el.shadowRoot.innerHTML, /Alive/);
});

test("does not claim to be alive when nothing is being drawn", async () => {
  const env = load();
  const calls = [];
  const el = card(env, { tablet: "wallpanel", interval: 30 }, async (msg) => { calls.push(msg); return { ok: true }; });
  await new Promise((r) => setImmediate(r));
  const before = calls.length;
  env.advance(60000); // no animation frame for 60 s with a 30 s interval
  await el._ping();
  assert.equal(calls.length, before);
  assert.match(el.shadowRoot.innerHTML, /Rendering stalled/);
});

test("stays quiet while the page is hidden", async () => {
  const env = load();
  const calls = [];
  const el = card(env, { tablet: "wallpanel" }, async (msg) => { calls.push(msg); return { ok: true }; });
  await new Promise((r) => setImmediate(r));
  const before = calls.length;
  env.visible.state = "hidden";
  await el._ping();
  assert.equal(calls.length, before);
});

test("an unknown tablet is reported", async () => {
  const env = load();
  const el = card(env, { tablet: "nope" }, async () => { const e = new Error("x"); e.code = "unknown_tablet"; throw e; });
  await new Promise((r) => setImmediate(r));
  assert.match(el.shadowRoot.innerHTML, /Unknown tablet &quot;nope&quot;/);
});

test("escapes what it renders", () => {
  const env = load();
  const el = new env.defined["ha-sidecar-beacon-card"]();
  el.setConfig({ tablet: "<img src=x onerror=alert(1)>" });
  assert.ok(!el.shadowRoot.innerHTML.includes("<img"));
});

test("announces that it left when the page navigates away", async () => {
  const env = load();
  const calls = [];
  card(env, { tablet: "wallpanel" }, async (msg) => { calls.push(JSON.parse(JSON.stringify(msg))); return { ok: true }; });
  await new Promise((r) => setImmediate(r));
  env.sandbox.window.location.pathname = "/config";
  for (const fn of env.sandbox.window.listeners["location-changed"]) fn();
  await new Promise((r) => setImmediate(r));
  const left = calls.find((c) => c.state === "inactive");
  assert.ok(left, "no leave notice sent");
  assert.equal(left.reason, "navigation");
  assert.equal(left.path, "/config");
});

test("announces when its view is unmounted and stops listening", async () => {
  const env = load();
  const calls = [];
  const el = card(env, { tablet: "wallpanel" }, async (msg) => { calls.push(JSON.parse(JSON.stringify(msg))); return { ok: true }; });
  await new Promise((r) => setImmediate(r));
  el.isConnected = false;
  el.disconnectedCallback();
  await new Promise((r) => setImmediate(r));
  assert.ok(calls.some((c) => c.state === "inactive" && /removed/.test(c.reason)));
  assert.equal(env.sandbox.window.listeners["location-changed"].length, 0);
});
