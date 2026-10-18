"""Tests for the microphone entities (echo cancellation, noise suppression, microphone source).

The sensor and the platform lists need the Home Assistant package (the lab venv has it); skipped when it is not installed. The
last test only reads files and always runs: it keeps the options Home Assistant offers equal to the values the tablet accepts.
"""

import re
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

try:
    from custom_components.ha_sidecar.config_entities import SELECTS, SWITCHES
    from custom_components.ha_sidecar.entity import add_entities
    from custom_components.ha_sidecar.sensor import EFFECT_STATES, EchoCancellationSensor

    HAVE_HA = True
except ImportError:  # pragma: no cover
    HAVE_HA = False


def device(state):
    return SimpleNamespace(
        device_id="tab-1", entity_prefix="wallpanel", name="Wall panel", info={}, state=state, connected=True, signal="sig"
    )


def kotlin_set(name: str) -> set[str]:
    """The words of `val <name> = setOf(...)` in MicEffects.kt."""
    source = (ROOT / "app/android/app/src/main/kotlin/dev/glassp/ha_sidecar/MicEffects.kt").read_text()
    match = re.search(rf"val {name} = setOf\(([^)]*)\)", source)
    assert match, name
    return set(re.findall(r'"([^"]+)"', match.group(1)))


@unittest.skipUnless(HAVE_HA, "needs Home Assistant")
class EchoCancellationSensorTest(unittest.TestCase):
    def test_the_tablets_unavailable_is_unsupported_in_home_assistant(self):
        # "unavailable" is the state Home Assistant gives an entity it cannot reach
        self.assertEqual(EFFECT_STATES["unavailable"], "unsupported")
        for wire, shown in [("active", "active"), ("idle", "idle"), ("unavailable", "unsupported"), ("disabled", "disabled")]:
            sensor = EchoCancellationSensor(device({"echo_cancellation_state": wire}))
            self.assertEqual(sensor.native_value, shown)
            self.assertIn(sensor.native_value, sensor.options)
        self.assertNotIn("unavailable", EchoCancellationSensor(device({})).options)

    def test_a_missing_or_unknown_state_is_unknown_not_an_error(self):
        self.assertIsNone(EchoCancellationSensor(device({})).native_value)
        self.assertIsNone(EchoCancellationSensor(device({"echo_cancellation_state": "bogus"})).native_value)

    def test_attributes_carry_noise_suppression_and_the_source(self):
        sensor = EchoCancellationSensor(
            device({"echo_cancellation_state": "active", "noise_suppression_state": "unavailable", "mic_source_in_use": "voice_recognition"})
        )
        self.assertEqual(
            sensor.extra_state_attributes, {"noise_suppression": "unsupported", "microphone_source": "voice_recognition"}
        )
        self.assertEqual(
            EchoCancellationSensor(device({})).extra_state_attributes, {"noise_suppression": None, "microphone_source": None}
        )

    def test_entity_ids_follow_the_naming_rules(self):
        added = []
        dev = device({})
        add_entities(dev, "sensor", added.extend, [EchoCancellationSensor(dev)])
        self.assertEqual(added[0].entity_id, "sensor.wallpanel_echo_cancellation")
        self.assertEqual(added[0].unique_id, "tab-1_echo_cancellation_state")
        self.assertEqual(added[0].entity_category.value, "diagnostic")

    def test_the_settings_are_entities_with_their_own_ids(self):
        selects = {key: (name, options) for key, name, options, _ in SELECTS}
        self.assertEqual(selects["echo_cancellation"], ("Echo cancellation mode", ["auto", "on", "off"]))
        self.assertEqual(selects["mic_source"][1], ["auto", "voice_recognition", "voice_communication"])
        self.assertIn("noise_suppression", [key for key, _, _ in SWITCHES])


class OptionsMatchTheTabletTest(unittest.TestCase):
    """The values the tablet accepts (MicEffects.kt) and the options Home Assistant offers are the same lists."""

    def test_echo_modes_and_sources(self):
        config = (ROOT / "custom_components/ha_sidecar/config_entities.py").read_text()
        for key, kotlin_name in [("echo_cancellation", "ECHO_MODES"), ("mic_source", "SOURCES")]:
            match = re.search(rf'\("{key}", "[^"]+", \[([^\]]*)\]', config)
            self.assertIsNotNone(match, key)
            self.assertEqual(set(re.findall(r'"([^"]+)"', match.group(1))), kotlin_set(kotlin_name), key)

    def test_the_state_words_are_the_ones_the_tablet_sends(self):
        source = (ROOT / "app/android/app/src/main/kotlin/dev/glassp/ha_sidecar/MicEffects.kt").read_text()
        words = set(re.findall(r'const val [A-Z]+ = "([a-z]+)"', source))
        self.assertEqual(words, {"active", "unavailable", "disabled", "idle"})
        sensor = (ROOT / "custom_components/ha_sidecar/sensor.py").read_text()
        match = re.search(r"EFFECT_STATES = \{([^}]*)\}", sensor)
        self.assertEqual(set(re.findall(r'"([a-z]+)":', match.group(1))), words)


if __name__ == "__main__":
    unittest.main()
