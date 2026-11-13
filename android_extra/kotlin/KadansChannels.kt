package nl.runwise.runwise

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Eigen kanalen van Kadans (geen extra pakketten nodig):
 *  - kadans/calendar: drukke tijden uit de telefoonagenda (alleen begin en eind, geen titels).
 *  - kadans/media (+ /events): de knop op je oortjes tijdens een run.
 *  - kadans/instagram: een afbeelding uit Kadans openen in Instagram (verhaal, of het keuzescherm van Instagram).
 *  - kadans/video: beelden (RGBA) één voor één omzetten naar een mp4 (H.264) voor de routevideo.
 *  - kadans/screen: tijdens een run het opnamescherm boven het vergrendelscherm tonen (geen ontgrendelen nodig).
 */
object KadansChannels {
    private var media: MediaButtons? = null

    fun register(activity: Activity, engine: FlutterEngine) {
        val ctx = activity.applicationContext
        val main = Handler(Looper.getMainLooper())
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "kadans/calendar").setMethodCallHandler { call, result ->
            when (call.method) {
                "busy" -> {
                    val from = (call.argument<Number>("from") ?: 0).toLong()
                    val to = (call.argument<Number>("to") ?: 0).toLong()
                    Thread {
                        try {
                            val list = readBusy(ctx, from, to)
                            main.post { result.success(list) }
                        } catch (e: SecurityException) {
                            main.post { result.error("permission", e.message, null) }
                        } catch (e: Exception) {
                            main.post { result.error("failed", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        val m = media ?: MediaButtons(ctx).also { media = it }
        MethodChannel(messenger, "kadans/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { m.start(); result.success(null) }
                "stop" -> { m.stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "kadans/instagram").setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> {
                    val path = call.argument<String>("path") ?: ""
                    val appId = call.argument<String>("appId") ?: ""
                    val sticker = call.argument<Boolean>("sticker") ?: false
                    val mime = call.argument<String>("mime") ?: "image/png"
                    val top = call.argument<String>("top") ?: "#13110E"
                    val bottom = call.argument<String>("bottom") ?: "#25201B"
                    try {
                        val pkg = "com.instagram.android"
                        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".kadans.deel", File(path))
                        val intent = if (appId.isNotEmpty()) {
                            // Rechtstreeks naar een nieuw verhaal (Meta vraagt hiervoor een App-ID).
                            Intent("com.instagram.share.ADD_TO_STORY").apply {
                                putExtra("source_application", appId)
                                if (sticker) {
                                    type = "image/png"
                                    putExtra("interactive_asset_uri", uri)
                                    putExtra("top_background_color", top)
                                    putExtra("bottom_background_color", bottom)
                                } else {
                                    setDataAndType(uri, mime)
                                }
                            }
                        } else {
                            // Zonder App-ID: Instagram laat zelf kiezen tussen verhaal, bericht, reel of chat.
                            Intent(Intent.ACTION_SEND).apply {
                                type = mime
                                putExtra(Intent.EXTRA_STREAM, uri)
                            }
                        }
                        intent.setPackage(pkg)
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        activity.grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        activity.startActivity(intent)
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    } catch (e: Exception) {
                        result.error("failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        val video = KadansVideo()
        MethodChannel(messenger, "kadans/video").setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> {
                    val path = call.argument<String>("path") ?: ""
                    val w = call.argument<Int>("width") ?: 720
                    val h = call.argument<Int>("height") ?: 1280
                    val fps = call.argument<Int>("fps") ?: 24
                    video.run(main, result) { video.begin(path, w, h, fps) }
                }
                "frame" -> {
                    val rgba = call.argument<ByteArray>("rgba")
                    val index = call.argument<Int>("index") ?: 0
                    if (rgba == null) result.error("failed", "geen beeld", null)
                    else video.run(main, result) { video.frame(rgba, index) }
                }
                "finish" -> video.run(main, result) { video.finish() }
                "cancel" -> video.run(main, result) { video.cancel() }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "kadans/screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "showOnLock" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    activity.runOnUiThread {
                        try {
                            if (Build.VERSION.SDK_INT >= 27) {
                                activity.setShowWhenLocked(on)
                            } else {
                                @Suppress("DEPRECATION")
                                if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                                else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("failed", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "kadans/media/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { m.sink = events }
            override fun onCancel(arguments: Any?) { m.sink = null }
        })
    }

    private fun readBusy(ctx: Context, from: Long, to: Long): List<Map<String, Long>> {
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, from)
        ContentUris.appendId(builder, to)
        val projection = arrayOf(
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.AVAILABILITY,
            CalendarContract.Instances.STATUS,
        )
        val out = mutableListOf<Map<String, Long>>()
        ctx.contentResolver.query(builder.build(), projection, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getInt(2) == 1) continue // hele dag: telt niet als bezet
                if (c.getInt(3) == CalendarContract.Instances.AVAILABILITY_FREE) continue
                if (c.getInt(4) == CalendarContract.Instances.STATUS_CANCELED) continue
                out.add(mapOf("b" to c.getLong(0), "e" to c.getLong(1)))
            }
        }
        return out
    }
}

/** Eén druk = pauze/verder, twee keer snel (of "volgende") = ronde. */
class MediaButtons(private val ctx: Context) {
    var sink: EventChannel.EventSink? = null
    private var session: MediaSession? = null
    private val main = Handler(Looper.getMainLooper())
    private var waiting = false
    private val single = Runnable { waiting = false; emit("toggle") }

    fun start() {
        if (session != null) return
        val s = MediaSession(ctx, "Kadans")
        s.setCallback(object : MediaSession.Callback() {
            override fun onMediaButtonEvent(intent: Intent): Boolean {
                @Suppress("DEPRECATION")
                val ev = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return false
                if (ev.action != KeyEvent.ACTION_DOWN || ev.repeatCount > 0) return true
                when (ev.keyCode) {
                    KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                    KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> click()
                    KeyEvent.KEYCODE_MEDIA_NEXT -> emit("lap")
                    else -> return false
                }
                return true
            }
        })
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT
                )
                .setState(PlaybackState.STATE_PLAYING, 0, 1f)
                .build()
        )
        s.isActive = true
        session = s
        playSilence()
    }

    fun stop() {
        main.removeCallbacks(single)
        waiting = false
        session?.let { it.isActive = false; it.release() }
        session = null
    }

    private fun click() {
        if (waiting) {
            main.removeCallbacks(single)
            waiting = false
            emit("lap")
        } else {
            waiting = true
            main.postDelayed(single, 450)
        }
    }

    private fun emit(e: String) = main.post { sink?.success(e) }

    /** Android stuurt de knop naar de app die het laatst geluid afspeelde: een halve seconde stilte is genoeg. */
    private fun playSilence() {
        try {
            val rate = 8000
            val samples = ShortArray(rate / 2)
            val track = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(samples.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            track.write(samples, 0, samples.size)
            track.play()
            main.postDelayed({ try { track.release() } catch (_: Exception) {} }, 800)
        } catch (_: Exception) {
        }
    }
}

/** Geeft Instagram leesrecht op het deelbeeld (alleen de map cache/deel, zie res/xml/kadans_share_paths.xml). */
class KadansFileProvider : FileProvider()

/** Zet RGBA-beelden met vaste tijdstippen om in een mp4 (H.264). Alles draait op één eigen draad, zodat de volgorde klopt. */
class KadansVideo {
    private val worker = Executors.newSingleThreadExecutor()
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var track = -1
    private var started = false
    private var w = 0
    private var h = 0
    private var fps = 24
    private val info = MediaCodec.BufferInfo()

    fun run(main: Handler, result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val r = block()
                main.post { result.success(r) }
            } catch (e: Exception) {
                release()
                main.post { result.error("failed", e.message ?: e.toString(), null) }
            }
        }
    }

    fun begin(path: String, width: Int, height: Int, rate: Int): Boolean {
        release()
        w = width; h = height; fps = rate
        File(path).delete()
        val fmt = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 5_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        c.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        c.start()
        codec = c
        muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        track = -1
        started = false
        return true
    }

    fun frame(rgba: ByteArray, index: Int): Boolean {
        val c = codec ?: throw IllegalStateException("encoder niet gestart")
        if (rgba.size < w * h * 4) throw IllegalArgumentException("beeld te klein")
        var i = c.dequeueInputBuffer(10_000)
        while (i < 0) {
            drain(false)
            i = c.dequeueInputBuffer(10_000)
        }
        val img = c.getInputImage(i) ?: throw IllegalStateException("geen invoerbeeld")
        fill(img, rgba)
        c.queueInputBuffer(i, 0, w * h * 3 / 2, index * 1_000_000L / fps, 0)
        drain(false)
        return true
    }

    fun finish(): Boolean {
        val c = codec ?: return false
        var i = c.dequeueInputBuffer(10_000)
        while (i < 0) {
            drain(false)
            i = c.dequeueInputBuffer(10_000)
        }
        c.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(true)
        release()
        return true
    }

    fun cancel(): Boolean {
        release()
        return true
    }

    private fun drain(untilEnd: Boolean) {
        val c = codec ?: return
        while (true) {
            val o = c.dequeueOutputBuffer(info, if (untilEnd) 10_000 else 0)
            when {
                o == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!untilEnd) return
                o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer!!.addTrack(c.outputFormat)
                    muxer!!.start()
                    started = true
                }
                o >= 0 -> {
                    val buf = c.getOutputBuffer(o)
                    if (buf != null && info.size > 0 && started && (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        muxer!!.writeSampleData(track, buf, info)
                    }
                    c.releaseOutputBuffer(o, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return
                }
            }
        }
    }

    private fun release() {
        try { codec?.stop() } catch (_: Exception) {}
        try { codec?.release() } catch (_: Exception) {}
        try { if (started) muxer?.stop() } catch (_: Exception) {}
        try { muxer?.release() } catch (_: Exception) {}
        codec = null; muxer = null; started = false; track = -1
    }

    /** RGBA naar YUV420 (BT.601, beperkt bereik) rechtstreeks in de vlakken van het invoerbeeld. */
    private fun fill(img: android.media.Image, rgba: ByteArray) {
        val yp = img.planes[0]; val up = img.planes[1]; val vp = img.planes[2]
        val yb = yp.buffer; val ub = up.buffer; val vb = vp.buffer
        for (y in 0 until h) {
            val row = y * w * 4
            val yo = y * yp.rowStride
            for (x in 0 until w) {
                val k = row + x * 4
                val r = rgba[k].toInt() and 0xFF
                val g = rgba[k + 1].toInt() and 0xFF
                val b = rgba[k + 2].toInt() and 0xFF
                yb.put(yo + x, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
            }
        }
        for (y in 0 until h / 2) {
            val uo = y * up.rowStride
            val vo = y * vp.rowStride
            for (x in 0 until w / 2) {
                var r = 0; var g = 0; var b = 0
                for (dy in 0..1) for (dx in 0..1) {
                    val k = ((y * 2 + dy) * w + (x * 2 + dx)) * 4
                    r += rgba[k].toInt() and 0xFF
                    g += rgba[k + 1].toInt() and 0xFF
                    b += rgba[k + 2].toInt() and 0xFF
                }
                r /= 4; g /= 4; b /= 4
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                ub.put(uo + x * up.pixelStride, u.coerceIn(0, 255).toByte())
                vb.put(vo + x * vp.pixelStride, v.coerceIn(0, 255).toByte())
            }
        }
    }
}
