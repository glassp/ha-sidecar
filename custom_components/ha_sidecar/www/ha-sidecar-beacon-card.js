/*
 * HA Sidecar beacon card.
 *
 * Put it on the dashboard a tablet shows. While the page is alive it pings Home Assistant every `interval` seconds over the
 * page's own connection and waits for the answer. If the page hangs, its renderer dies or it loses its connection, the pings
 * stop, and the HA Sidecar integration can restart the companion app (Settings > Devices & services > HA Sidecar >
 * Configure). Nothing is sent unless this card is on a dashboard.
 *
 *   type: custom:ha-sidecar-beacon-card
 *   tablet: wallpanel        # the entity prefix of the tablet
 *   interval: 30             # seconds (optional)
 *   compact: false           # hide the status line (optional)
 *
 * Note: a dashboard view only runs the cards of the view that is showing. On a dashboard with several views put the card on
 * every view the tablet can be on, or the silence of a view without it looks like a hang.
 */

const CARD_NAME = "ha-sidecar-beacon-card";
const ANSWER_TIMEOUT_MS = 10000;

const esc = (value) =>
  String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

class HaSidecarBeaconCard extends HTMLElement {
  constructor() {
    super();
    this._config = null;
    this._hass = null;
    this._timer = null;
    this._rafId = null;
    this._lastFrame = performance.now();
    this._status = { kind: "waiting", text: "Waiting" };
    this._leaving = () => this._announceLeft("navigation", true);
    this._pageHide = () => this._announceLeft("page unloaded", false);
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
    return { type: `custom:${CARD_NAME}`, tablet };
  }

  setConfig(config) {
    if (!config || !config.tablet) {
      throw new Error("Choose a tablet (the entity prefix of an HA Sidecar tablet).");
    }
    this._config = { interval: 30, compact: false, ...config };
    this._stop();
    this._render();
    if (this.isConnected) this._start();
  }

  set hass(hass) {
    this._hass = hass;
    if (this.isConnected && !this._timer) this._start();
  }

  getCardSize() {
    return this._config && this._config.compact ? 0 : 1;
  }

  connectedCallback() {
    this._start();
  }

  disconnectedCallback() {
    // the view with this card is no longer shown: say so, so that silence is not mistaken for a hang
    this._announceLeft("card removed from the page", false);
    this._stop();
  }

  _start() {
    if (this._timer || !this._config || !this._hass) return;
    // an animation frame only runs while the page is really being drawn: a stuck compositor stops it
    const loop = () => {
      this._lastFrame = performance.now();
      this._rafId = requestAnimationFrame(loop);
    };
    loop();
    const every = Math.max(5, Number(this._config.interval) || 30) * 1000;
    // leaving the page on purpose (another dashboard, a reload) is announced, not mistaken for a freeze
    window.addEventListener("location-changed", this._leaving);
    window.addEventListener("popstate", this._leaving);
    window.addEventListener("pagehide", this._pageHide);
    window.addEventListener("beforeunload", this._pageHide);
    this._ping();
    this._timer = setInterval(() => this._ping(), every);
  }

  _stop() {
    if (this._timer) clearInterval(this._timer);
    if (this._rafId) cancelAnimationFrame(this._rafId);
    this._timer = null;
    this._rafId = null;
    window.removeEventListener("location-changed", this._leaving);
    window.removeEventListener("popstate", this._leaving);
    window.removeEventListener("pagehide", this._pageHide);
    window.removeEventListener("beforeunload", this._pageHide);
  }

  /** Tells Home Assistant this card is not on the page being shown any more (best effort: the page may be unloading). */
  _announceLeft(reason, maybeStillHere) {
    if (!this._hass || !this._config) return;
    this._set("paused", "Left the page");
    Promise.resolve(
      this._hass.callWS({ type: "ha_sidecar/beacon", tablet: this._config.tablet, state: "inactive", reason, path: window.location.pathname }),
    ).catch(() => {});
    if (maybeStillHere) {
      // a navigation inside the same view keeps this card mounted: announce that it is active again
      setTimeout(() => { if (this.isConnected) this._ping(); }, 1500);
    }
  }

  async _ping() {
    if (!this._hass || !this._config) return;
    if (document.visibilityState === "hidden") {
      this._set("paused", "Page hidden");
      return;
    }
    const every = Math.max(5, Number(this._config.interval) || 30) * 1000;
    if (performance.now() - this._lastFrame > every * 1.5) {
      // JS runs but nothing is being drawn: do not report "alive"
      this._set("bad", "Rendering stalled");
      return;
    }
    try {
      const answer = await Promise.race([
        this._hass.callWS({ type: "ha_sidecar/beacon", tablet: this._config.tablet, state: "active", path: window.location.pathname }),
        new Promise((_, reject) => setTimeout(() => reject(new Error("no answer")), ANSWER_TIMEOUT_MS)),
      ]);
      this._set("ok", `Alive ${new Date().toLocaleTimeString()}`, answer);
    } catch (err) {
      const unknown = err && err.code === "unknown_tablet";
      this._set("bad", unknown ? `Unknown tablet "${this._config.tablet}"` : "Home Assistant did not answer");
    }
  }

  _set(kind, text) {
    this._status = { kind, text };
    this._render();
  }

  _render() {
    const compact = this._config && this._config.compact;
    const colors = { ok: "var(--success-color, #43a047)", bad: "var(--error-color, #db4437)", paused: "var(--secondary-text-color)", waiting: "var(--secondary-text-color)" };
    const { kind, text } = this._status;
    this.shadowRoot.innerHTML = `
      <style>
        :host { display: block; }
        ha-card { display: ${compact ? "none" : "block"}; }
        .row { display: flex; align-items: center; gap: 10px; padding: 8px 16px; font-size: 14px; color: var(--primary-text-color); }
        .dot { width: 10px; height: 10px; border-radius: 50%; background: ${colors[kind]}; flex: none; }
        .tablet { color: var(--secondary-text-color); margin-left: auto; }
      </style>
      <ha-card><div class="row"><span class="dot"></span><span>${esc(text)}</span><span class="tablet">${esc(this._config ? this._config.tablet : "")}</span></div></ha-card>`;
  }
}

class HaSidecarBeaconCardEditor extends HTMLElement {
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
        <label>Ping every (seconds)
          <input id="interval" type="number" min="5" max="300" value="${this._config.interval || 30}">
        </label>
        <label><input id="compact" type="checkbox" ${this._config.compact ? "checked" : ""}> Hide the status line</label>`;
    }
    this.innerHTML = `
      <style>
        label { display: block; margin: 12px 0; }
        select, input[type=number] { display: block; width: 100%; margin-top: 4px; padding: 8px; box-sizing: border-box; }
      </style>${body}`;
    const q = (id) => this.querySelector(`#${id}`);
    if (q("tablet")) q("tablet").addEventListener("change", (e) => this._changed({ tablet: e.target.value }));
    if (q("interval")) q("interval").addEventListener("change", (e) => this._changed({ interval: Number(e.target.value) || 30 }));
    if (q("compact")) q("compact").addEventListener("change", (e) => this._changed({ compact: e.target.checked }));
  }
}

customElements.define(CARD_NAME, HaSidecarBeaconCard);
customElements.define(`${CARD_NAME}-editor`, HaSidecarBeaconCardEditor);

window.customCards = window.customCards || [];
window.customCards.push({
  type: CARD_NAME,
  name: "HA Sidecar beacon",
  description: "Lets Home Assistant notice when the dashboard on a tablet freezes, and restart the app.",
  preview: false,
});
