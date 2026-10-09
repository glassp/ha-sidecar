"""Constants for HA Sidecar."""

DOMAIN = "ha_sidecar"
VERSION = "0.1.0"  # also in manifest.json; cache-busts the card URL

CONF_DEVICE_ID = "device_id"
CONF_TOKEN = "token"
CONF_ENTITY_PREFIX = "entity_prefix"  # entity ids are <domain>.<prefix>_<entity>

PROTOCOL_VERSION = 1
WS_PATH = "/api/ha_sidecar/ws"

# Bus event fired for app events (alarm_ringing, alarm_stopped, system_update_pending, ...)
EVENT_SIDECAR = "ha_sidecar_event"

COMMAND_TIMEOUT = 20
ANNOUNCE_TIMEOUT = 120  # an announcement blocks until it has been played

# Options (Configure on the integration card)
CONF_PRESENCE_ENTITIES = "presence_entities"  # on = someone is near the tablet (mmWave, PIR, ...)
CONF_GLANCE_ENTITIES = "glance_entities"  # values shown on the at-a-glance screen
CONF_BEACON_HEAL = "beacon_heal"  # restart the companion app when the dashboard beacon goes silent
CONF_BEACON_TIMEOUT = "beacon_timeout"  # minutes of silence before that
CONF_NIGHT_ENTITY = "night_entity"  # sun.sun (below_horizon) or any on/off entity: on = night
