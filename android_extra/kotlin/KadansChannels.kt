package nl.runwise.runwise

import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Eigen kanalen van Kadans (geen extra pakketten nodig):
 *  - kadans/calendar: drukke tijden uit de telefoonagenda (alleen begin en eind, geen titels).
 *  - kadans/media (+ /events): de knop op je oortjes tijdens een run.
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
