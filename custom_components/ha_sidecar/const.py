"""Constants for HA Sidecar."""

DOMAIN = "ha_sidecar"

CONF_DEVICE_ID = "device_id"
CONF_TOKEN = "token"

PROTOCOL_VERSION = 1
WS_PATH = "/api/ha_sidecar/ws"

# Bus event fired for app events (alarm_ringing, alarm_stopped, system_update_pending, ...)
EVENT_SIDECAR = "ha_sidecar_event"

COMMAND_TIMEOUT = 20
