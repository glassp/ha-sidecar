package dev.glassp.ha_sidecar

import android.content.Context
import org.tensorflow.lite.Interpreter
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/**
 * On-device wake word with openWakeWord models (docs/VOICE.md): a mel spectrogram model, an embedding model and one small
 * classifier per phrase. The models are not part of the app: they are downloaded on the device when the user switches the wake
 * word on (their licence does not allow shipping them), and verified against the hashes below.
 */
object WakeWordModels {
    enum class Source(val label: String) {
        OPENWAKEWORD("openWakeWord (CC BY-NC-SA 4.0)"),
        COMMUNITY("community collection, trained with openWakeWord (MIT)"),
    }

    class Model(
        val id: String,
        val phrase: String,
        val file: String,
        val url: String,
        val sha256: String,
        val size: Long,
        val source: Source = Source.OPENWAKEWORD,
    )

    private const val UP = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/"

    /** The two models every phrase needs (mel spectrogram, embedding). */
    val shared = listOf(
        Model("melspectrogram", "", "melspectrogram.tflite", UP + "melspectrogram.tflite", "96fa0adccb6e8cf95cb14465409a1a2898ee4a96a85bb9ed3c7eb0e68bf163e8", 1_092_516),
        Model("embedding", "", "embedding_model.tflite", UP + "embedding_model.tflite", "c0aea21eb84a4ce90a08c870da41b7a7173b45269e6a3207c71d67c40f3a59d8", 1_330_312),
    )

    /**
     * The phrases on offer. Every classifier takes 16 embeddings and returns one score. The community ones come from a collection
     * pinned to one commit; each file is pinned by hash too. (No model for "Hey Siri" or "OK Google" exists publicly; "Hal" and "Skynet"
     * were left out because they did not react to speech in the lab.)
     */
    val words = listOf(
        Model("hey_jarvis", "Hey Jarvis", "hey_jarvis_v0.1.tflite", "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_jarvis_v0.1.tflite", "14bff778604985e1b5c19f0f7bbe477a69cf281d8db34b232b3b972411f710e2", 1278912, Source.OPENWAKEWORD),
        Model("alexa", "Alexa", "alexa_v0.1.tflite", "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/alexa_v0.1.tflite", "7333a317a790070a7f3432b81d9439c779481cc4ebd67c73da7174ea3cf48397", 855312, Source.OPENWAKEWORD),
        Model("hey_mycroft", "Hey Mycroft", "hey_mycroft_v0.1.tflite", "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_mycroft_v0.1.tflite", "bf9e43136afd3ca323698820a6e32a47f885ef4c30a3b8b577ec71688a9d64d8", 860300, Source.OPENWAKEWORD),
        Model("hey_rhasspy", "Hey Rhasspy", "hey_rhasspy_v0.1.tflite", "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/hey_rhasspy_v0.1.tflite", "01d2526b45068f565aa3849d6ec2b7abae099154fc1b496f9ef20de9ef241fe9", 416140, Source.OPENWAKEWORD),
        Model("jarvis", "Jarvis", "jarvis.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/jarvis/jarvis_v2.tflite", "cb2102fc9a76d4e02a740760d5ba2060978d766869489000b3565c8c4f8493a5", 207512, Source.COMMUNITY),
        Model("ok_jarvis", "OK Jarvis", "ok_jarvis.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/ok_jarvis/ok_jarvis.tflite", "e38bf1970b4954f3a63e3cec53d866dd068d37d132f20ffc74bc620901cd81c2", 206380, Source.COMMUNITY),
        Model("computer", "Computer", "computer.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/computer/computer_v2.tflite", "411db364955bf7b7a13a50d732a8b59c129e2fbe130a54f9eb3c20ca183bc4d0", 207512, Source.COMMUNITY),
        Model("ok_computer", "OK Computer", "ok_computer.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/ok_computer/ok_computer.tflite", "b22dadba0f1c6ac2549a1336e8938f3e2366b3f43a3e95a622ca897aa5a3477a", 206380, Source.COMMUNITY),
        Model("hey_nabu", "Hey Nabu", "hey_nabu.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/hey_nabu/hey_nabu_v2.tflite", "ce18b69e1bddfb56e70fe739d6ca0f423f70a6e710f05b376baf6a3625689234", 207512, Source.COMMUNITY),
        Model("ok_nabu", "OK Nabu", "ok_nabu.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/ok_nabu/ok_nabu.tflite", "3961c87ba68996ad904f22597e432a136f726cb6441960c5e535eb073299ee25", 206380, Source.COMMUNITY),
        Model("home_assistant", "Home Assistant", "home_assistant.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/home_assistant/Home_assistant.tflite", "9f54305884abde30d484f18dbff582ed6e2f1a141b93d6fa5f7feb505a0c94aa", 206380, Source.COMMUNITY),
        Model("ok_home", "OK Home", "ok_home.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/ok_home/ok_home.tflite", "6b314b3935d37b6f0b4319527ad3664b76672bbd6b1d870d56a0b5dda4c543e1", 206380, Source.COMMUNITY),
        Model("hey_friday", "Hey Friday", "hey_friday.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/hey_friday/hey_Friday%21.tflite", "eb127d82d884a1ef4167b455ec67682bf362b9de3e232c3f8d544a5e6ab4cb8b", 206748, Source.COMMUNITY),
        Model("marvin", "Marvin", "marvin.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/marvin/marvin_v2.tflite", "ed91c4d83e28bcc0af1cdebe3ab4f2a4f2d4c9908101ad8476d2e1b9b77f4e0c", 207512, Source.COMMUNITY),
        Model("hey_kitt", "Hey KITT", "hey_kitt.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/hey_kitt/hey_kitt.tflite", "c698353e6ade9633eab0e478f67d84e80a0b27674c86d738e0c8874a5f37d4f9", 207512, Source.COMMUNITY),
        Model("hey_spock", "Hey Spock", "hey_spock.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/hey_spock/hey_spock.tflite", "f39eb339c0c2b18315e085a0cc4debcc7d74dd2d0b35585d3d4c49a0acec89d3", 206748, Source.COMMUNITY),
        Model("alfred", "Alfred", "alfred.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/alfred/alfred.tflite", "ee50efc6898d065eaf6a5a993d10be0d6a1bb6737ba577d623fa3d1327e2310e", 206380, Source.COMMUNITY),
        Model("glados", "GLaDOS", "glados.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/glados/glados.tflite", "7564b95e5deed29cecfd55fd34cac70da5307c0d86108a7f87bfc610c9724dec", 207512, Source.COMMUNITY),
        Model("terminator", "Terminator", "terminator.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/terminator/Terminator.tflite", "7feb69397a56a6933d3248ecca3ca6aaca7b6bf2c36f5beb9b63bb3d17647686", 206380, Source.COMMUNITY),
        Model("mr_anderson", "Mr. Anderson", "mr_anderson.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/mr_anderson/Mr._Anderson.tflite", "e7ffc82ef0de12bba5c51aa5326af8339bc4f95a43dd15246893408643aa978b", 206380, Source.COMMUNITY),
        Model("hey_house", "Hey House", "hey_house.tflite", "https://raw.githubusercontent.com/fwartner/home-assistant-wakewords-collection/8bcd2f20bb7b76c351b2eff871fa1ce873fe9be2/en/hey_house/hey_house.tflite", "924833a5fe62e57db229798452051fe9ee76b723619f5dd2c86bf12e58318098", 206748, Source.COMMUNITY),
    )

    const val DEFAULT_ID = "hey_jarvis"

    fun dir(ctx: Context) = File(ctx.filesDir, "wakeword").also { it.mkdirs() }
    fun word(id: String) = words.firstOrNull { it.id == id }

    private fun present(ctx: Context, m: Model) = File(dir(ctx), m.file).let { it.isFile && it.length() == m.size }
    private fun sharedPresent(ctx: Context) = shared.all { present(ctx, it) }

    /** The phrases whose classifier (and the two shared models) are on the device. */
    fun installedWords(ctx: Context): List<String> =
        if (sharedPresent(ctx)) words.filter { present(ctx, it) }.map { it.id } else emptyList()

    /** Bytes still to download for [wordId] (0 = ready): its classifier and, if missing, the shared models. */
    fun missingBytes(ctx: Context, wordId: String): Long {
        val w = word(wordId) ?: return 0
        return (shared + w).filter { !present(ctx, it) }.sumOf { it.size }
    }

    /**
     * Downloads what [wordId] needs, verifying every file; blocking, call from a worker thread.
     * @return null on success or an error code (download_failed, hash_mismatch, unknown_word, no_space).
     */
    fun download(ctx: Context, wordId: String, progress: (done: Long, total: Long) -> Unit): String? {
        val w = word(wordId) ?: return "unknown_word"
        val todo = (shared + w).filter { !present(ctx, it) }
        val total = todo.sumOf { it.size }
        if (dir(ctx).usableSpace < total * 2) return "no_space"
        var done = 0L
        for (m in todo) {
            val tmp = File(dir(ctx), m.file + ".part")
            try {
                val conn = (URL(m.url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15_000
                    readTimeout = 30_000
                    instanceFollowRedirects = true
                }
                if (conn.responseCode != 200) return "download_failed"
                val md = MessageDigest.getInstance("SHA-256")
                conn.inputStream.use { input ->
                    tmp.outputStream().use { out ->
                        val buf = ByteArray(32 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            md.update(buf, 0, n)
                            done += n
                            progress(done, total)
                        }
                    }
                }
                val hex = md.digest().joinToString("") { "%02x".format(it) }
                if (hex != m.sha256 || tmp.length() != m.size) {
                    tmp.delete()
                    return "hash_mismatch"
                }
                if (!tmp.renameTo(File(dir(ctx), m.file))) return "download_failed"
            } catch (e: Exception) {
                tmp.delete()
                return "download_failed"
            }
        }
        return null
    }

    /** Deletes the classifier of [wordId]; the shared models go with the last one. */
    fun remove(ctx: Context, wordId: String) {
        val w = word(wordId) ?: return
        File(dir(ctx), w.file).delete()
        File(dir(ctx), w.file + ".part").delete()
        if (words.none { present(ctx, it) }) shared.forEach { File(dir(ctx), it.file).delete() }
    }
}

/**
 * The melspectrogram model is stored with the input shape [1, 1], which its convolutions cannot be allocated for, and the Java
 * interpreter allocates when it is created. This rewrites the shape of the first input to [1, [samples]] in a copy of the model
 * (a minimal FlatBuffers reader: Model.subgraphs[0].inputs[0] -> Subgraph.tensors[i].shape); the engine resizes it per call anyway.
 */
object TfliteShape {
    private fun u16(b: ByteBuffer, p: Int) = b.getShort(p).toInt() and 0xffff
    private fun u32(b: ByteBuffer, p: Int) = b.getInt(p)

    /** Position of field [field] of the table at [table], or -1 if it is absent. */
    private fun field(b: ByteBuffer, table: Int, field: Int): Int {
        val vtable = table - b.getInt(table)
        val slot = 4 + 2 * field
        if (slot >= u16(b, vtable)) return -1
        val off = u16(b, vtable + slot)
        return if (off == 0) -1 else table + off
    }

    private fun vector(b: ByteBuffer, pos: Int) = pos + u32(b, pos) // position of the length word

    /** @return a patched copy as a direct buffer, or null if the file does not have the expected structure. */
    fun withInputShape(model: ByteArray, shape: IntArray): ByteBuffer? = runCatching {
        val b = ByteBuffer.allocateDirect(model.size).order(ByteOrder.LITTLE_ENDIAN)
        b.put(model)
        val root = u32(b, 0)
        val subgraphs = vector(b, field(b, root, 2).also { require(it >= 0) })
        val subgraph = subgraphs + 4 + u32(b, subgraphs + 4) // element 0 of the table vector
        val inputs = vector(b, field(b, subgraph, 1).also { require(it >= 0) })
        val inputIndex = u32(b, inputs + 4)
        val tensors = vector(b, field(b, subgraph, 0).also { require(it >= 0) })
        val tensorEntry = tensors + 4 + 4 * inputIndex
        val tensor = tensorEntry + u32(b, tensorEntry)
        val shapeVec = vector(b, field(b, tensor, 0).also { require(it >= 0) })
        require(u32(b, shapeVec) == shape.size)
        for (i in shape.indices) b.putInt(shapeVec + 4 + 4 * i, shape[i])
        b.rewind()
        b
    }.getOrNull()
}

/**
 * The openWakeWord streaming pipeline, feeding 80 ms (1280 samples of 16 kHz PCM16) at a time:
 * mel model over the new samples plus 30 ms of context, embedding model over the last 76 mel frames, classifier over the
 * last 16 embeddings. Mirrors the reference implementation (checked against a Python port, docs/TESTING.md).
 */
class WakeWordEngine(ctx: Context, private val wordIds: List<String>) : AutoCloseable {
    companion object {
        const val CHUNK = 1280
        private const val CONTEXT = 160 * 3
        private const val MEL_BINS = 32
        private const val EMB_FRAMES = 76
        private const val EMB_DIM = 96
        private const val CLS_FRAMES = 16
        private const val WARMUP_CHUNKS = 16 // the classifier window is only real audio after 16 embeddings
        private const val THREADS = 2 // TFLite threads for the embedding and word models: the default pool burned about 20% more CPU (Pixel 6, 58% -> 47% of a core)
    }

    private val dir = WakeWordModels.dir(ctx)
    private val mel = Interpreter(
        TfliteShape.withInputShape(File(dir, "melspectrogram.tflite").readBytes(), intArrayOf(1, CHUNK + CONTEXT))
            ?: throw IllegalStateException("melspectrogram model has an unexpected layout"),
        Interpreter.Options().setUseXNNPACK(false),
    )
    private val emb = Interpreter(File(dir, "embedding_model.tflite"), Interpreter.Options().setNumThreads(THREADS))
    private val classifiers = wordIds.associateWith { id ->
        Interpreter(File(dir, WakeWordModels.word(id)!!.file), Interpreter.Options().setNumThreads(THREADS)).also {
            check(it.getInputTensor(0).shape().contentEquals(intArrayOf(1, CLS_FRAMES, EMB_DIM)) && it.getOutputTensor(0).numElements() == 1) {
                "wake word model $id does not take 16 embeddings and return one score"
            }
        }
    }

    private val raw = FloatArray(CHUNK + CONTEXT)
    private var rawCount = 0
    private val melFrames = ArrayDeque<FloatArray>()
    private val embeddings = ArrayDeque<FloatArray>()
    private var chunks = 0
    private var melInputLen = -1
    private var melOutFrames = 0

    init {
        reset()
    }

    fun reset() {
        rawCount = 0
        melFrames.clear()
        repeat(EMB_FRAMES) { melFrames.addLast(FloatArray(MEL_BINS) { 1f }) }
        embeddings.clear()
        chunks = 0
    }

    private fun direct(floats: Int) = ByteBuffer.allocateDirect(floats * 4).order(ByteOrder.nativeOrder())

    /** Scores for one chunk of exactly [CHUNK] samples: phrase id to 0..1 (all 0 while warming up). */
    fun feed(pcm: ShortArray): Map<String, Float> {
        require(pcm.size == CHUNK)
        // keep the newest CHUNK + CONTEXT samples
        val keep = minOf(rawCount, CONTEXT)
        if (keep > 0) System.arraycopy(raw, rawCount - keep, raw, 0, keep)
        for (i in 0 until CHUNK) raw[keep + i] = pcm[i].toFloat()
        rawCount = keep + CHUNK

        runMel(rawCount)
        runEmbedding()
        chunks++

        val result = LinkedHashMap<String, Float>()
        for ((id, interp) in classifiers) {
            var score = 0f
            if (chunks >= WARMUP_CHUNKS) {
                val input = direct(CLS_FRAMES * EMB_DIM)
                for (e in embeddings.toList().takeLast(CLS_FRAMES)) for (v in e) input.putFloat(v)
                input.rewind()
                val out = direct(1)
                interp.run(input, out)
                out.rewind()
                score = out.float
            }
            result[id] = score
        }
        return result
    }

    private fun runMel(samples: Int) {
        if (samples != melInputLen) {
            mel.resizeInput(0, intArrayOf(1, samples))
            mel.allocateTensors()
            melInputLen = samples
            melOutFrames = mel.getOutputTensor(0).shape()[2]
        }
        val input = direct(samples)
        for (i in 0 until samples) input.putFloat(raw[i])
        input.rewind()
        val out = direct(melOutFrames * MEL_BINS)
        mel.run(input, out)
        out.rewind()
        repeat(melOutFrames) {
            val frame = FloatArray(MEL_BINS) { out.float / 10f + 2f }
            melFrames.addLast(frame)
            if (melFrames.size > EMB_FRAMES) melFrames.removeFirst()
        }
    }

    private fun runEmbedding() {
        val input = direct(EMB_FRAMES * MEL_BINS)
        for (f in melFrames) for (v in f) input.putFloat(v)
        input.rewind()
        val out = direct(EMB_DIM)
        emb.run(input, out)
        out.rewind()
        embeddings.addLast(FloatArray(EMB_DIM) { out.float })
        if (embeddings.size > CLS_FRAMES) embeddings.removeFirst()
    }

    override fun close() {
        runCatching { mel.close() }
        runCatching { emb.close() }
        classifiers.values.forEach { runCatching { it.close() } }
    }
}

/** The wake word as a feature: configuration, readiness (models, permission), the downloads and the detection event. */
object WakeWord {
    @Volatile var wanted = false // enabled and at least one chosen phrase is ready: the microphone loop feeds the engine
    @Volatile var activeIds: List<String> = emptyList() // the chosen phrases that are on the device (what the engine listens for)
    @Volatile var threshold = 0.5f
    @Volatile var listening = false // the engine is loaded and fed
    @Volatile var error: String? = null // models_missing | mic_permission | start_blocked | mic_failed | engine_failed
    @Volatile var lastScore = 0f
    @Volatile var downloading: String? = null // the phrase being downloaded
    @Volatile var downloadFraction = 0.0
    @Volatile var downloadError: String? = null
    private val queue = java.util.concurrent.LinkedBlockingDeque<String>()

    /** The chosen phrases from the settings (a comma separated list of catalogue ids). */
    fun chosen(cfg: Map<String, Any>): List<String> =
        (cfg["wake_word_ids"] as String).split(',').map { it.trim() }.filter { WakeWordModels.word(it) != null }.distinct()

    /** Re-reads the settings and starts or ends the listening. Safe to call often. */
    fun refresh(ctx: Context) {
        val cfg = DisplayConfig.get(ctx)
        threshold = (cfg["wake_word_threshold"] as Int) / 100f
        val enabled = cfg["wake_word"] == true
        val chosen = chosen(cfg)
        val installed = WakeWordModels.installedWords(ctx)
        activeIds = chosen.filter { it in installed }
        wanted = false
        error = null
        if (!enabled) downloadError = null
        if (enabled && chosen.isNotEmpty()) {
            val missing = chosen.filter { it !in installed }
            if (missing.isNotEmpty()) {
                if (activeIds.isEmpty()) error = "models_missing"
                // choosing a phrase is the consent to fetch its model; a failed attempt waits for the user's retry
                if (downloadError == null) missing.forEach { enqueue(ctx, it) }
            }
            if (activeIds.isNotEmpty()) {
                Voice.ensurePermission(ctx)
                if (!Voice.hasPermission(ctx)) {
                    error = "mic_permission"
                } else {
                    wanted = true
                    if (!Voice.ensureMic(ctx)) {
                        wanted = false
                        error = "start_blocked"
                    }
                }
            }
        }
        EventBus.emit("status_changed")
    }

    private const val TRACE_FLOOR = 0.2f
    private const val TRACE_EVERY_MS = 500L
    private var lastTrace = 0L // the microphone thread only

    /**
     * Logs a score worth a look (a near miss, a hit, the tablet hearing itself) together with the microphone setup it came through,
     * so a run with echo cancellation on can be compared with one that has it off: `adb logcat -s WakeWord` (docs/VOICE.md).
     */
    fun trace(id: String, score: Float, now: Long) {
        if (score < TRACE_FLOOR || now - lastTrace < TRACE_EVERY_MS) return
        lastTrace = now
        android.util.Log.i("WakeWord", "score $id %.3f (threshold %.2f) ${MicEffects.label()}".format(score, threshold))
    }

    fun detected(id: String, score: Float) {
        android.util.Log.i("WakeWord", "detected $id %.3f ${MicEffects.label()}".format(score))
        EventBus.emit("wake_word", mapOf("id" to id, "phrase" to (WakeWordModels.word(id)?.phrase ?: id), "score" to score.toDouble()))
    }

    fun engineFailed(t: Throwable) {
        error = "engine_failed"
        wanted = false
        EventBus.emit("status_changed")
    }

    fun micFailed(code: String) {
        error = code
        wanted = false
        EventBus.emit("status_changed")
    }

    /** Queues the download of [id] (a retry after a failure clears the error); downloads run one after the other. */
    fun download(ctx: Context, id: String) {
        downloadError = null
        enqueue(ctx, id)
        refresh(ctx)
    }

    @Synchronized
    private fun enqueue(ctx: Context, id: String) {
        if (WakeWordModels.word(id) == null || downloading == id || id in queue || WakeWordModels.missingBytes(ctx, id) == 0L) return
        queue.addLast(id)
        if (downloading != null) return
        downloading = queue.peekFirst()
        Thread({ work(ctx.applicationContext) }, "wakeword-download").start()
    }

    private fun work(ctx: Context) {
        while (true) {
            val id = synchronized(this) { queue.pollFirst().also { downloading = it } } ?: break
            downloadFraction = 0.0
            EventBus.emit("status_changed")
            val err = WakeWordModels.download(ctx, id) { done, total ->
                val f = done.toDouble() / total.coerceAtLeast(1)
                if (f - downloadFraction >= 0.02) {
                    downloadFraction = f
                    EventBus.emit("status_changed")
                }
            }
            if (err != null) {
                downloadError = err
                queue.clear() // do not hammer a broken connection with the rest of the queue
            }
            refresh(ctx)
        }
        downloading = null
        refresh(ctx)
    }

    /** Deletes the model of [id] and takes it out of the chosen phrases. */
    fun remove(ctx: Context, id: String) {
        queue.remove(id)
        val cfg = DisplayConfig.get(ctx)
        val rest = chosen(cfg).filter { it != id }
        // set() refreshes us; the file goes first so the engine is rebuilt without it
        WakeWordModels.remove(ctx, id)
        DisplayConfig.set(ctx, mapOf("wake_word_ids" to rest.joinToString(",")))
    }

    fun snapshot(ctx: Context): Map<String, Any?> {
        val installed = WakeWordModels.installedWords(ctx)
        val chosen = chosen(DisplayConfig.get(ctx))
        return mapOf(
            "wake_word_listening" to listening,
            "wake_word_error" to error,
            "wake_word_score" to lastScore.toDouble(),
            "wake_word_downloading" to downloading,
            "wake_word_download_fraction" to downloadFraction,
            "wake_word_download_error" to downloadError,
            "wake_words" to WakeWordModels.words.map {
                mapOf(
                    "id" to it.id,
                    "phrase" to it.phrase,
                    "installed" to (it.id in installed),
                    "active" to (it.id in chosen),
                    "size_bytes" to it.size,
                    "missing_bytes" to WakeWordModels.missingBytes(ctx, it.id),
                    "downloading" to (it.id == downloading),
                    "queued" to (it.id in queue),
                    "source" to it.source.label,
                )
            },
        )
    }
}

/**
 * Debug builds only: `adb shell am broadcast -a dev.glassp.ha_sidecar.WW_SCORE --es path <wav in the app's files dir> --es word hey_jarvis`
 * scores a 16 kHz mono PCM16 wav (with a second of silence around it) and logs one score per 80 ms chunk under the tag WWTEST.
 * Used to compare the engine with the reference implementation (docs/TESTING.md).
 */
object WakeWordDebug {
    private var registered = false

    @Synchronized
    fun register(ctx: Context) {
        if (registered || ctx.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        registered = true
        val filter = android.content.IntentFilter("dev.glassp.ha_sidecar.WW_SCORE").apply { addAction("dev.glassp.ha_sidecar.WW_INJECT") }
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(c: Context, i: android.content.Intent) {
                val path = i.getStringExtra("path") ?: return
                val word = i.getStringExtra("word") ?: "hey_jarvis"
                if (i.action == "dev.glassp.ha_sidecar.WW_INJECT") {
                    // plays the file (with silence before and after) into the microphone loop, as if it was spoken
                    Thread({
                        runCatching {
                            val pcm = readPcm(File(ctx.filesDir, path))
                            val q = java.util.concurrent.ConcurrentLinkedQueue<ShortArray>()
                            var pos = 0
                            val padded = ShortArray(16000 + pcm.size + 16000).also { System.arraycopy(pcm, 0, it, 16000, pcm.size) }
                            while (pos + WakeWordEngine.CHUNK <= padded.size) {
                                q.add(padded.copyOfRange(pos, pos + WakeWordEngine.CHUNK))
                                pos += WakeWordEngine.CHUNK
                            }
                            Voice.debugInject = q
                            android.util.Log.i("WWTEST", "injecting ${q.size} frames of $path")
                        }
                    }, "wwinject").start()
                } else Thread({ score(ctx, File(ctx.filesDir, path), word) }, "wwtest").start()
            }
        }
        // debug builds only (see the guard above): exported on purpose, so that `adb shell am broadcast` reaches it
        androidx.core.content.ContextCompat.registerReceiver(ctx, receiver, filter, androidx.core.content.ContextCompat.RECEIVER_EXPORTED)
    }

    /** The samples of a 16 kHz mono PCM16 wav. */
    private fun readPcm(wav: File): ShortArray {
        val bytes = wav.readBytes()
        // walk the RIFF chunks to the audio (afconvert writes a padded header, not a canonical 44-byte one)
        var at = 12
        var start = -1
        var len = 0
        while (at + 8 <= bytes.size) {
            val size = (bytes[at + 4].toInt() and 0xff) or ((bytes[at + 5].toInt() and 0xff) shl 8) or
                ((bytes[at + 6].toInt() and 0xff) shl 16) or ((bytes[at + 7].toInt() and 0xff) shl 24)
            if (String(bytes, at, 4) == "data") {
                start = at + 8
                len = minOf(size, bytes.size - start)
                break
            }
            at += 8 + size + (size and 1)
        }
        require(start >= 0) { "no data chunk" }
        val data = bytes.copyOfRange(start, start + len)
        return ShortArray(data.size / 2) { ((data[2 * it].toInt() and 0xff) or (data[2 * it + 1].toInt() shl 8)).toShort() }
    }

    private fun score(ctx: Context, wav: File, word: String) {
        try {
            val audio = readPcm(wav)
            val pcm = ShortArray(16000 + audio.size + 16000).also { System.arraycopy(audio, 0, it, 16000, audio.size) }
            val engine = WakeWordEngine(ctx, listOf(word))
            var best = 0f
            val sb = StringBuilder()
            var k = 0
            var pos = 0
            while (pos + WakeWordEngine.CHUNK <= pcm.size) {
                val s = engine.feed(pcm.copyOfRange(pos, pos + WakeWordEngine.CHUNK))[word] ?: 0f
                best = maxOf(best, s)
                sb.append(String.format("%d:%.4f ", k, s))
                pos += WakeWordEngine.CHUNK
                k++
            }
            engine.close()
            android.util.Log.i("WWTEST", "${wav.name} $word max=%.4f chunks=$k".format(best))
            android.util.Log.i("WWTEST", "scores ${sb.toString().trim()}")
        } catch (e: Throwable) {
            android.util.Log.e("WWTEST", "failed: " + android.util.Log.getStackTraceString(e))
        }
    }
}
