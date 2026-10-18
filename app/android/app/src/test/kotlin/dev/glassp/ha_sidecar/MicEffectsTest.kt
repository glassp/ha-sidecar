package dev.glassp.ha_sidecar

import android.media.MediaRecorder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The choices behind the microphone setup (settings -> source and effects, effect -> diagnostic state). The effects themselves
 * ([MicEffects.attach]) need a device with an audio server and are checked on a tablet (docs/TABLET_TRIAL.md).
 */
class MicEffectsTest {
    private val recognition = MediaRecorder.AudioSource.VOICE_RECOGNITION
    private val communication = MediaRecorder.AudioSource.VOICE_COMMUNICATION

    @Test fun defaultsKeepTheSourceTheLoopAlwaysUsedAndAskForEchoCancellationOnly() {
        val plan = MicPlan.of(mapOf("echo_cancellation" to "auto", "noise_suppression" to false, "mic_source" to "auto"))
        assertEquals(MicPlan(recognition, echo = true, noise = false), plan)
        assertEquals("a config without the keys behaves the same", plan, MicPlan.of(emptyMap()))
    }

    @Test fun echoCancellationIsOffOnlyWhenTheSettingSaysOff() {
        for (mode in listOf("auto", "on")) assertTrue(mode, MicPlan.of(mapOf("echo_cancellation" to mode)).echo)
        assertFalse(MicPlan.of(mapOf("echo_cancellation" to "off")).echo)
    }

    @Test fun noiseSuppressionIsOffUnlessSwitchedOn() {
        assertFalse(MicPlan.of(mapOf("noise_suppression" to false)).noise)
        assertFalse("not a boolean", MicPlan.of(mapOf("noise_suppression" to "yes")).noise)
        assertTrue(MicPlan.of(mapOf("noise_suppression" to true)).noise)
    }

    @Test fun theSourceFollowsTheSetting() {
        assertEquals(recognition, MicPlan.of(mapOf("mic_source" to "auto")).source)
        assertEquals(recognition, MicPlan.of(mapOf("mic_source" to "voice_recognition")).source)
        assertEquals(communication, MicPlan.of(mapOf("mic_source" to "voice_communication")).source)
    }

    @Test fun anUnknownValueFallsBackToTheDefaults() {
        val plan = MicPlan.of(mapOf("mic_source" to "nonsense", "echo_cancellation" to 3, "noise_suppression" to null))
        assertEquals(MicPlan(recognition, echo = true, noise = false), plan)
    }

    @Test fun everyAcceptedSettingValueHasTheDefaultAmongThem() {
        assertEquals(setOf("auto", "on", "off"), MicPlan.ECHO_MODES)
        assertEquals(setOf("auto", "voice_recognition", "voice_communication"), MicPlan.SOURCES)
        // the sources the settings can name are told apart in logs and in the status
        assertEquals("voice_recognition", MicPlan.nameOf(recognition))
        assertEquals("voice_communication", MicPlan.nameOf(communication))
        assertEquals("voice_communication", MicPlan.of(mapOf("mic_source" to "voice_communication")).sourceName)
    }

    @Test fun aChangedSetupIsADifferentPlanSoTheLoopRestarts() {
        val base = MicPlan.of(emptyMap())
        assertEquals(base, MicPlan.of(mapOf("echo_cancellation" to "on")))
        assertFalse(base == MicPlan.of(mapOf("echo_cancellation" to "off")))
        assertFalse(base == MicPlan.of(mapOf("noise_suppression" to true)))
        assertFalse(base == MicPlan.of(mapOf("mic_source" to "voice_communication")))
    }

    @Test fun anEffectNobodyAskedForIsDisabledWhateverTheDeviceHas() {
        assertEquals(EffectState.DISABLED, EffectState.of(wanted = false, supported = true, failed = false, attached = false))
        assertEquals(EffectState.DISABLED, EffectState.of(wanted = false, supported = false, failed = false, attached = false))
        assertEquals("a stale attachment does not make a switched-off effect active", EffectState.DISABLED,
            EffectState.of(wanted = false, supported = true, failed = false, attached = true))
    }

    @Test fun aDeviceWithoutTheEffectOrWhereItFailedIsUnavailable() {
        assertEquals(EffectState.UNAVAILABLE, EffectState.of(wanted = true, supported = false, failed = false, attached = false))
        assertEquals(EffectState.UNAVAILABLE, EffectState.of(wanted = true, supported = true, failed = true, attached = false))
    }

    @Test fun anAttachedEffectIsActiveAndOtherwiseItWaitsForTheMicrophone() {
        assertEquals(EffectState.ACTIVE, EffectState.of(wanted = true, supported = true, failed = false, attached = true))
        assertEquals(EffectState.IDLE, EffectState.of(wanted = true, supported = true, failed = false, attached = false))
    }

    @Test fun theStateWordsAreTheOnesTheProtocolDocuments() {
        assertEquals(setOf("active", "unavailable", "disabled", "idle"),
            setOf(EffectState.ACTIVE, EffectState.UNAVAILABLE, EffectState.DISABLED, EffectState.IDLE))
    }
}
