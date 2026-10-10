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
    const val BASE = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1/"

    class Model(val id: String, val phrase: String, val file: String, val sha256: String, val size: Long)

    val shared = listOf(
        Model("melspectrogram", "", "melspectrogram.tflite", "96fa0adccb6e8cf95cb14465409a1a2898ee4a96a85bb9ed3c7eb0e68bf163e8", 1_092_516),
        Model("embedding", "", "embedding_model.tflite", "c0aea21eb84a4ce90a08c870da41b7a7173b45269e6a3207c71d67c40f3a59d8", 1_330_312),
    )
    val words = listOf(
        Model("hey_jarvis", "Hey Jarvis", "hey_jarvis_v0.1.tflite", "14bff778604985e1b5c19f0f7bbe477a69cf281d8db34b232b3b972411f710e2", 1_278_912),
        Model("alexa", "Alexa", "alexa_v0.1.tflite", "7333a317a790070a7f3432b81d9439c779481cc4ebd67c73da7174ea3cf48397", 855_312),
        Model("hey_mycroft", "Hey Mycroft", "hey_mycroft_v0.1.tflite", "bf9e43136afd3ca323698820a6e32a47f885ef4c30a3b8b577ec71688a9d64d8", 860_300),
    )

    fun dir(ctx: Context) = File(ctx.filesDir, "wakeword").also { it.mkdirs() }
    fun word(id: String) = words.firstOrNull { it.id == id }

    private fun present(ctx: Context, m: Model) = File(dir(ctx), m.file).let { it.isFile && it.length() == m.size }

    /** The phrases whose models (and the two shared ones) are on the device. */
    fun installedWords(ctx: Context): List<String> =
        if (shared.all { present(ctx, it) }) words.filter { present(ctx, it) }.map { it.id } else emptyList()

    /** Bytes still to download for [wordId] (0 = ready). */
    fun missingBytes(ctx: Context, wordId: String): Long {
        val w = word(wordId) ?: return 0
        return (shared + w).filter { !present(ctx, it) }.sumOf { it.size }
    }

    /**
     * Downloads what [wordId] needs, verifying every file; blocking, call from a worker thread.
     * @return null on success or an error code (`download_failed`, `hash_mismatch`, `unknown_word`, `no_space`).
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
                val conn = (URL(BASE + m.file).openConnection() as HttpURLConnection).apply {
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
    }

    private val dir = WakeWordModels.dir(ctx)
    private val mel = Interpreter(
        TfliteShape.withInputShape(File(dir, "melspectrogram.tflite").readBytes(), intArrayOf(1, CHUNK + CONTEXT))
            ?: throw IllegalStateException("melspectrogram model has an unexpected layout"),
        Interpreter.Options().setUseXNNPACK(false),
    )
    private val emb = Interpreter(File(dir, "embedding_model.tflite"))
    private val classifiers = wordIds.associateWith { id ->
        Interpreter(File(dir, WakeWordModels.word(id)!!.file))
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

/** The wake word as a feature: configuration, readiness (models, permission), the download and the detection event. */
object WakeWord {
    @Volatile var wanted = false // enabled and ready: the microphone loop feeds the engine
    @Volatile var activeId = "hey_jarvis"
    @Volatile var threshold = 0.5f
    @Volatile var listening = false // the engine is loaded and fed
    @Volatile var error: String? = null // models_missing | mic_permission | start_blocked | mic_failed | engine_failed
    @Volatile var lastScore = 0f
    @Volatile var downloading: String? = null // the phrase being downloaded
    @Volatile var downloadFraction = 0.0
    @Volatile var downloadError: String? = null

    /** Re-reads the settings and starts or ends the listening. Safe to call often. */
    fun refresh(ctx: Context) {
        val cfg = DisplayConfig.get(ctx)
        activeId = cfg["wake_word_id"] as String
        threshold = (cfg["wake_word_threshold"] as Int) / 100f
        val enabled = cfg["wake_word"] == true
        wanted = false
        error = null
        if (!enabled) downloadError = null
        if (enabled) {
            if (activeId !in WakeWordModels.installedWords(ctx)) {
                error = "models_missing"
                // switching the wake word on is the consent to fetch its models; a failed attempt waits for the user's retry
                if (downloading == null && downloadError == null) download(ctx, activeId)
            } else {
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

    fun detected(id: String, score: Float) {
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

    /** Downloads the models for [id] in the background, then switches to them. Progress shows in the status. */
    fun download(ctx: Context, id: String) {
        if (downloading != null) return
        downloading = id
        downloadFraction = 0.0
        downloadError = null
        EventBus.emit("status_changed")
        Thread({
            val err = WakeWordModels.download(ctx, id) { done, total ->
                val f = done.toDouble() / total.coerceAtLeast(1)
                if (f - downloadFraction >= 0.02) {
                    downloadFraction = f
                    EventBus.emit("status_changed")
                }
            }
            downloadError = err
            downloading = null
            refresh(ctx)
        }, "wakeword-download").start()
    }

    fun snapshot(ctx: Context): Map<String, Any?> = mapOf(
        "wake_word_listening" to listening,
        "wake_word_error" to error,
        "wake_word_score" to lastScore.toDouble(),
        "wake_word_downloading" to downloading,
        "wake_word_download_fraction" to downloadFraction,
        "wake_word_download_error" to downloadError,
        "wake_words" to WakeWordModels.words.map {
            mapOf("id" to it.id, "phrase" to it.phrase, "installed" to (it.id in WakeWordModels.installedWords(ctx)), "missing_bytes" to WakeWordModels.missingBytes(ctx, it.id))
        },
    )
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
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            ctx.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else ctx.registerReceiver(receiver, filter)
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
