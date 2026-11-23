package com.example.teacher_center;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.view.View;
import android.widget.RemoteViews;

import es.antonborri.home_widget.HomeWidgetProvider;

public class NextSessionWidgetProvider extends HomeWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds, SharedPreferences widgetData) {
        for (int widgetId : appWidgetIds) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.next_session_widget);

            boolean hasSession = widgetData.getBoolean("widget_has_session", false);
            String title = widgetData.getString("widget_title", "الحصة القادمة اليوم");
            String groupName = widgetData.getString("widget_group_name", "لا توجد حصص متبقية اليوم");
            String grade = widgetData.getString("widget_grade", "سنتر أستاذي التعليمي");
            String time = widgetData.getString("widget_time", "--:--");
            String room = widgetData.getString("widget_room", "");
            String groupId = widgetData.getString("widget_group_id", "");

            views.setTextViewText(R.id.widget_title, title != null ? title : "الحصة القادمة اليوم");
            views.setTextViewText(R.id.widget_group_name, groupName != null ? groupName : "لا توجد حصص متبقية اليوم");
            views.setTextViewText(R.id.widget_grade, grade != null ? grade : "سنتر أستاذي التعليمي");
            views.setTextViewText(R.id.widget_time, time != null ? time : "--:--");

            if (room != null && !room.trim().isEmpty()) {
                views.setTextViewText(R.id.widget_room, room);
                views.setViewVisibility(R.id.widget_room, View.VISIBLE);
            } else {
                views.setViewVisibility(R.id.widget_room, View.GONE);
            }

            if (hasSession) {
                views.setTextViewText(R.id.widget_action_btn, "تسجيل الحضور ➔");
                views.setViewVisibility(R.id.widget_action_btn, View.VISIBLE);
            } else {
                views.setTextViewText(R.id.widget_action_btn, "فتح البرنامج");
                views.setViewVisibility(R.id.widget_action_btn, View.VISIBLE);
            }

            // Launch intent when user clicks anywhere on the widget or action button
            Uri uri;
            if (hasSession && groupId != null && !groupId.trim().isEmpty()) {
                uri = Uri.parse("eduacademy://session?groupId=" + groupId);
            } else {
                uri = Uri.parse("eduacademy://home");
            }

            Intent launchIntent = new Intent(context, MainActivity.class);
            launchIntent.setAction(Intent.ACTION_VIEW);
            launchIntent.setData(uri);
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);

            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }

            PendingIntent pendingIntent = PendingIntent.getActivity(context, widgetId, launchIntent, flags);
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent);
            views.setOnClickPendingIntent(R.id.widget_action_btn, pendingIntent);

            appWidgetManager.updateAppWidget(widgetId, views);
        }
    }
}
