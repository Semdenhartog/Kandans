package nl.runwise.runwise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Startscherm-widget: je beste vertrekmoment van vandaag. De app werkt hem bij als je Vandaag opent. */
class BestMomentWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.best_moment_widget).apply {
                setTextViewText(R.id.widget_label, widgetData.getString("label", "BESTE MOMENT"))
                setTextViewText(R.id.widget_time, widgetData.getString("time", "--:--"))
                setTextViewText(R.id.widget_detail, widgetData.getString("detail", "Open Kadans voor je beste moment"))
                setTextViewText(R.id.widget_updated, widgetData.getString("updated", ""))
                setImageViewResource(
                    R.id.widget_icon,
                    when (widgetData.getString("glyph", "sun")) {
                        "moon" -> R.drawable.widget_moon
                        "cloud" -> R.drawable.widget_cloud
                        "rain" -> R.drawable.widget_rain
                        else -> R.drawable.widget_sun
                    },
                )
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
