/*
 * HA Sidecar timers card.
 *
 * Shows the timers and stopwatches of a tablet, live, on any dashboard, with pause / resume, +1 minute and cancel. The
 * timers run on the tablet (they keep running when Home Assistant is away); this card only displays and controls them,
 * so voice timers ("set a timer for 10 minutes") appear here too.
 *
 *   type: custom:ha-sidecar-timers-card
 *   tablet: wallpanel          # the entity prefix of the tablet
 *   hide_when_empty: true      # show nothing while there is no timer (default)
 *   title: Timers              # optional
 */

const CARD_NAME = "ha-sidecar-timers-card";

const esc = (value) =>
  String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const clock = (seconds) => {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const two = (n) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${two(m)}:${two(sec)}` : `${m}:${two(sec)}`;
};

const RING = 2 * Math.PI * 22;

class HaSidecarTimersCard extends HTMLElement {
  constructor() {
    super();
    this._config = null;
    this._hass = null;
    this._timers = [];
    this._signature = "";
    this._tick = null;
    this._deviceId = null;
    this.attachShadow({ mode: "open" });
  }

  static getConfigElement() {
    return document.createElement(`${CARD_NAME}-editor`);
  }

  static async getStubConfig(hass) {
    let tablet = "";
    try {
      const tablets = await hass.callWS({ type: "ha_sidecar/tablets" });
      tablet = tablets.length ? tablets[0].prefix : "";
    } catch (_) {
      /* the integration is not set up: the editor explains it */
    }
    return { type: `custom:${CARD_NAME}`, tablet, hide_when_empty: true };
  }

  setConfig(config) {
    if (!config || !config.tablet) {
      throw new Error("Choose a tablet (the entity prefix of an HA Sidecar tablet).");
    }
    this._config = { hide_when_empty: true, ...config };
    this._deviceId = null;
    this._signature = "";
    this._build();
    this._read();
  }

  set hass(hass) {
    this._hass = hass;
    this._read();
  }

  getCardSize() {
    return Math.max(1, Math.ceil(this._timers.length / 2) * 2);
  }

  connectedCallback() {
    if (!this._tick) this._tick = setInterval(() => this._refresh(), 1000);
  }

  disconnectedCallback() {
    if (this._tick) clearInterval(this._tick);
    this._tick = null;
  }

  get _entity() {
    return `sensor.${this._config.tablet}_timers`;
  }

  /** The timers from the entity's attributes; the tiles are only rebuilt when the set or the state of a timer changes. */
  _read() {
    if (!this._hass || !this._config) return;
    const st = this._hass.states[this._entity];
    const timers = st && Array.isArray(st.attributes.timers) ? st.attributes.timers : [];
    const signature = JSON.stringify(timers.map((t) => [t.timer_id, t.state, t.label, t.duration, t.ends_at, t.remaining, t.finished_at]));
    this._missing = !st;
    if (signature === this._signature) return;
    this._signature = signature;
    this._timers = timers;
    this._build();
  }

  async _device() {
    if (this._deviceId) return this._deviceId;
    const entry = this._hass.entities && this._hass.entities[this._entity];
    if (entry && entry.device_id) return (this._deviceId = entry.device_id);
    const tablets = await this._hass.callWS({ type: "ha_sidecar/tablets" });
    const t = tablets.find((x) => x.prefix === this._config.tablet);
    if (!t) throw new Error("unknown tablet");
    return (this._deviceId = t.device_id);
  }

  async _act(service, timer, data = {}) {
    try {
      const device_id = await this._device();
      await this._hass.callService("ha_sidecar", service, { device_id, timer_id: timer.timer_id, ...data });
    } catch (err) {
      /* the entity updates when the tablet has acted; a failure (tablet offline) leaves the card as it is */
    }
  }

  /** Seconds to show and the ring fraction (1 = full) for a timer, from the end time the tablet reported. */
  _values(t, now) {
    const countdown = t.kind === "countdown";
    if (countdown) {
      const left = t.state === "running" && t.ends_at ? (Date.parse(t.ends_at) - now) / 1000 : t.remaining;
      const since = t.finished_at || t.ends_at;
      const over = t.state === "finished" ? Math.max(0, since ? (now - Date.parse(since)) / 1000 : 0) : 0;
      return { seconds: t.state === "finished" ? over : Math.max(0, left), fraction: t.duration ? Math.max(0, Math.min(1, left / t.duration)) : 0, over: t.state === "finished" };
    }
    const elapsed = t.state === "running" && t.started_at ? (now - Date.parse(t.started_at)) / 1000 : t.elapsed;
    return { seconds: Math.max(0, elapsed), fraction: 1, over: false };
  }

  _build() {
    if (!this._config) return;
    const empty = !this._timers.length;
    const hide = empty && this._config.hide_when_empty && !this._missing;
    const tiles = this._timers
      .map((t) => {
        const finished = t.state === "finished";
        const paused = t.state === "paused";
        const countdown = t.kind === "countdown";
        const name = t.label || (countdown ? "Timer" : "Stopwatch");
        return `
          <div class="tile ${finished ? "done" : ""} ${paused ? "paused" : ""}" data-id="${esc(t.timer_id)}">
            <div class="ring">
              <svg viewBox="0 0 52 52"><circle class="track" cx="26" cy="26" r="22"/><circle class="arc" cx="26" cy="26" r="22" stroke-dasharray="${RING}" stroke-dashoffset="0"/></svg>
              <ha-icon icon="${finished ? "mdi:bell-ring" : paused ? "mdi:pause" : countdown ? "mdi:timer-sand" : "mdi:timer-outline"}"></ha-icon>
            </div>
            <div class="text"><div class="time" data-time>0:00</div><div class="name">${esc(name)}</div></div>
            <div class="buttons">
              ${finished ? "" : `<button data-act="${paused ? "resume_timer" : "pause_timer"}" title="${paused ? "Resume" : "Pause"}"><ha-icon icon="${paused ? "mdi:play" : "mdi:pause"}"></ha-icon></button>`}
              ${countdown ? `<button data-act="plus" title="+1 min"><span>+1</span></button>` : ""}
              <button data-act="cancel_timer" title="${finished ? "Dismiss" : "Cancel"}"><ha-icon icon="mdi:close"></ha-icon></button>
            </div>
          </div>`;
      })
      .join("");
    const title = this._config.title ? `<div class="title">${esc(this._config.title)}</div>` : "";
    const note = this._missing ? `<div class="note">Unknown tablet "${esc(this._config.tablet)}" (no ${esc(this._entity)}).</div>` : "";
    this.shadowRoot.innerHTML = `
      <style>
        :host { display: block; }
        ha-card { display: ${hide ? "none" : "block"}; padding: 12px 16px 16px; }
        .title { font-size: 16px; font-weight: 500; color: var(--primary-text-color); padding: 0 0 8px; }
        .note, .empty { color: var(--secondary-text-color); font-size: 14px; padding: 8px 0; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 10px; }
        .tile { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border-radius: 16px;
                background: var(--secondary-background-color, rgba(127,127,127,.12)); }
        .tile.done { background: color-mix(in srgb, var(--error-color, #db4437) 22%, transparent); }
        .tile.paused .time { opacity: .6; }
        .ring { position: relative; width: 52px; height: 52px; flex: none; }
        .ring svg { position: absolute; inset: 0; transform: rotate(-90deg); }
        .ring circle { fill: none; stroke-width: 4; }
        .track { stroke: var(--divider-color, rgba(127,127,127,.3)); }
        .arc { stroke: var(--primary-color); stroke-linecap: round; }
        .done .arc { stroke: var(--error-color, #db4437); }
        .ring ha-icon { position: absolute; inset: 0; display: grid; place-items: center; --mdc-icon-size: 22px; color: var(--primary-text-color); }
        .text { min-width: 0; flex: 1; }
        .time { font-size: 24px; font-weight: 500; line-height: 1.1; color: var(--primary-text-color); font-variant-numeric: tabular-nums; }
        .done .time { color: var(--error-color, #db4437); }
        .name { font-size: 13px; color: var(--secondary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .buttons { display: flex; gap: 4px; flex: none; }
        button { all: unset; cursor: pointer; width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center;
                 color: var(--primary-text-color); font-size: 13px; font-weight: 600; --mdc-icon-size: 20px; }
        button:hover { background: var(--divider-color, rgba(127,127,127,.25)); }
      </style>
      <ha-card>${title}${note}<div class="grid">${tiles}</div></ha-card>`;
    this.shadowRoot.querySelectorAll("[data-act]").forEach((b) =>
      b.addEventListener("click", (e) => {
        const id = e.currentTarget.closest(".tile").dataset.id;
        const timer = this._timers.find((t) => t.timer_id === id);
        if (!timer) return;
        const act = e.currentTarget.dataset.act;
        if (act === "plus") this._act("adjust_timer", timer, { seconds: 60 });
        else this._act(act, timer);
      }),
    );
    this._refresh();
  }

  /** Every second: only the numbers and rings change; the buttons are not touched. */
  _refresh() {
    if (!this._config) return;
    const now = Date.now();
    this.shadowRoot.querySelectorAll(".tile").forEach((tile) => {
      const t = this._timers.find((x) => x.timer_id === tile.dataset.id);
      if (!t) return;
      const v = this._values(t, now);
      const time = tile.querySelector("[data-time]");
      const text = (v.over ? "+" : "") + clock(v.seconds);
      if (time.textContent !== text) time.textContent = text;
      tile.querySelector(".arc").setAttribute("stroke-dashoffset", String(RING * (1 - v.fraction)));
    });
  }
}

class HaSidecarTimersCardEditor extends HTMLElement {
  setConfig(config) {
    this._config = config;
    this._render();
  }

  set hass(hass) {
    const first = !this._hass;
    this._hass = hass;
    if (first) this._load();
  }

  async _load() {
    try {
      this._tablets = await this._hass.callWS({ type: "ha_sidecar/tablets" });
    } catch (_) {
      this._tablets = null;
    }
    this._render();
  }

  _changed(patch) {
    this._config = { ...this._config, ...patch };
    this.dispatchEvent(new CustomEvent("config-changed", { detail: { config: this._config }, bubbles: true, composed: true }));
  }

  _render() {
    if (!this._config) return;
    const tablets = this._tablets;
    let body;
    if (tablets === undefined) {
      body = "<p>Loading tablets…</p>";
    } else if (!tablets || !tablets.length) {
      body = "<p>No HA Sidecar tablet is set up in Home Assistant yet.</p>";
    } else {
      const options = tablets
        .map((t) => `<option value="${esc(t.prefix)}" ${t.prefix === this._config.tablet ? "selected" : ""}>${esc(t.name)} (${esc(t.prefix)})</option>`)
        .join("");
      body = `
        <label>Tablet
          <select id="tablet"><option value="" ${this._config.tablet ? "" : "selected"}>Choose…</option>${options}</select>
        </label>
        <label>Title (optional)
          <input id="title" type="text" value="${esc(this._config.title || "")}">
        </label>
        <label><input id="hide" type="checkbox" ${this._config.hide_when_empty !== false ? "checked" : ""}> Hide the card while there is no timer</label>`;
    }
    this.innerHTML = `
      <style>
        label { display: block; margin: 12px 0; }
        select, input[type=text] { display: block; width: 100%; margin-top: 4px; padding: 8px; box-sizing: border-box; }
      </style>${body}`;
    const q = (id) => this.querySelector(`#${id}`);
    if (q("tablet")) q("tablet").addEventListener("change", (e) => this._changed({ tablet: e.target.value }));
    if (q("title")) q("title").addEventListener("change", (e) => this._changed({ title: e.target.value }));
    if (q("hide")) q("hide").addEventListener("change", (e) => this._changed({ hide_when_empty: e.target.checked }));
  }
}

// Same wait as the beacon card: Home Assistant swaps `customElements` for a scoped registry after extra modules ran, and the
// dashboard only finds cards defined in that one. `ha-card` is defined by the frontend, so wait for it (with a timeout).
function defineElements() {
  customElements.define(CARD_NAME, HaSidecarTimersCard);
  customElements.define(`${CARD_NAME}-editor`, HaSidecarTimersCardEditor);
}

function defineWhenFrontendIsReady() {
  const frontendReady = () => typeof customElements.get !== "function" || Boolean(customElements.get("ha-card"));
  let waited = 0;
  const poll = () => {
    if (frontendReady() || (waited += 50) > 30000) defineElements();
    else setTimeout(poll, 50);
  };
  poll();
}

defineWhenFrontendIsReady();

window.customCards = window.customCards || [];
window.customCards.push({
  type: CARD_NAME,
  name: "HA Sidecar timers",
  description: "The timers and stopwatches of a tablet, live, with pause, +1 minute and cancel.",
  preview: false,
});
