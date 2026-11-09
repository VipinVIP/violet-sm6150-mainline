/* LD_PRELOAD shim: edge swipe (left or right screen edge, inward) => Android back.
 * Hooks gtk_window_present() to attach a GtkGestureDrag to every GtkWindow once, and
 * calls ATL's current_activity_back_pressed() (exported by libtranslation_layer_main.so).
 * The gesture never claims the touch sequence, so apps still receive all events.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gtk/gtk.h>
#include <math.h>
#include <stdio.h>

#define EDGE_PX     48.0   /* touch must start this close to the left/right edge */
#define MIN_DX_PX   70.0   /* horizontal travel needed (logical px) */
#define MAX_SLOPE   0.6    /* |dy| / |dx| limit */
#define CLAIM_DX_PX 12.0   /* sideways travel after which we take the touch away from the app */

static void (*back_pressed)(void);

static void drag_begin(GtkGestureDrag *g, double x, double y, gpointer data)
{
	GtkWidget *w = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(g));
	double width = gtk_widget_get_width(w);
	gboolean *armed = data;
	*armed = (x <= EDGE_PX || x >= width - EDGE_PX);
}

static void drag_update(GtkGestureDrag *g, double dx, double dy, gpointer data)
{
	gboolean *armed = data;
	/* Like Android's system back gesture, win over the app (e.g. NewPipe's left-edge drawer)
	 * once the edge drag is clearly horizontal. */
	if (*armed && fabs(dx) > CLAIM_DX_PX && fabs(dy) < fabs(dx) * MAX_SLOPE)
		gtk_gesture_set_state(GTK_GESTURE(g), GTK_EVENT_SEQUENCE_CLAIMED);
}

static void drag_end(GtkGestureDrag *g, double dx, double dy, gpointer data)
{
	gboolean *armed = data;
	if (!*armed)
		return;
	*armed = FALSE;
	GtkWidget *w = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(g));
	double sx, sy;
	gtk_gesture_drag_get_start_point(g, &sx, &sy);
	double width = gtk_widget_get_width(w);
	gboolean from_left = sx <= EDGE_PX && dx > 0;
	gboolean from_right = sx >= width - EDGE_PX && dx < 0;
	if (!(from_left || from_right))
		return;
	if (fabs(dx) < MIN_DX_PX || fabs(dy) > fabs(dx) * MAX_SLOPE)
		return;
	if (!back_pressed)
		back_pressed = dlsym(RTLD_DEFAULT, "current_activity_back_pressed");
	if (back_pressed) {
		fprintf(stderr, "atl-swipe-back: edge swipe -> back\n");
		back_pressed();
	}
}

void gtk_window_present(GtkWindow *window)
{
	static void (*real)(GtkWindow *);
	if (!real)
		real = dlsym(RTLD_NEXT, "gtk_window_present");

	if (!g_object_get_data(G_OBJECT(window), "atl-swipe-back")) {
		gboolean *armed = g_new0(gboolean, 1);
		GtkGesture *g = gtk_gesture_drag_new();
		/* touch only on the phone; ATL_SWIPE_BACK_ANY_POINTER=1 lets a mouse drag trigger it (testing over VNC) */
		gtk_gesture_single_set_touch_only(GTK_GESTURE_SINGLE(g), !g_getenv("ATL_SWIPE_BACK_ANY_POINTER"));
		gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(g), GTK_PHASE_CAPTURE);
		g_signal_connect(g, "drag-begin", G_CALLBACK(drag_begin), armed);
		g_signal_connect(g, "drag-update", G_CALLBACK(drag_update), armed);
		g_signal_connect(g, "drag-end", G_CALLBACK(drag_end), armed);
		gtk_widget_add_controller(GTK_WIDGET(window), GTK_EVENT_CONTROLLER(g));
		g_object_set_data(G_OBJECT(window), "atl-swipe-back", GINT_TO_POINTER(1));
	}
	real(window);
}
