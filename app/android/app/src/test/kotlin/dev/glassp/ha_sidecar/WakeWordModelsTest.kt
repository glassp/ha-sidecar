package dev.glassp.ha_sidecar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WakeWordModelsTest {
    private val all get() = WakeWordModels.shared + WakeWordModels.words

    @Test fun idsFilesAndPhrasesAreUnique() {
        assertEquals(WakeWordModels.words.size, WakeWordModels.words.map { it.id }.toSet().size)
        assertEquals(all.size, all.map { it.file }.toSet().size)
        assertEquals(WakeWordModels.words.size, WakeWordModels.words.map { it.phrase.lowercase() }.toSet().size)
        assertTrue(WakeWordModels.words.all { it.phrase.isNotBlank() && it.id.matches(Regex("[a-z0-9_]+")) })
    }

    @Test fun everyDownloadIsPinned() {
        for (m in all) {
            assertTrue("${m.id} hash", m.sha256.matches(Regex("[0-9a-f]{64}")))
            assertTrue("${m.id} size", m.size in 100_000..5_000_000)
            assertTrue("${m.id} https", m.url.startsWith("https://"))
        }
        // community models come from one commit of the collection, never from a moving branch
        for (m in WakeWordModels.words.filter { it.source == WakeWordModels.Source.COMMUNITY }) {
            assertTrue("${m.id} pinned", Regex("/home-assistant-wakewords-collection/[0-9a-f]{40}/").containsMatchIn(m.url))
        }
        for (m in WakeWordModels.words.filter { it.source == WakeWordModels.Source.OPENWAKEWORD }) {
            assertTrue("${m.id} release", m.url.contains("/dscripka/openWakeWord/releases/download/v0.5.1/"))
        }
    }

    @Test fun theDefaultPhraseExistsAndTheCommonNamesAreOffered() {
        assertTrue(WakeWordModels.word(WakeWordModels.DEFAULT_ID) != null)
        for (id in listOf("alexa", "hey_jarvis", "jarvis", "computer", "hey_mycroft", "ok_nabu", "hey_nabu")) {
            assertTrue("$id offered", WakeWordModels.word(id) != null)
        }
    }

    @Test fun chosenKeepsKnownPhrasesOnceInOrder() {
        val cfg = mapOf<String, Any>("wake_word_ids" to " alexa,nope, hey_jarvis ,alexa,,computer")
        assertEquals(listOf("alexa", "hey_jarvis", "computer"), WakeWord.chosen(cfg))
        assertEquals(emptyList<String>(), WakeWord.chosen(mapOf("wake_word_ids" to "")))
    }
}
