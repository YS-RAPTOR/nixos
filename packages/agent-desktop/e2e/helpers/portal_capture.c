#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include <gst/gst.h>
#include <libportal/portal.h>
#include <libportal/remote.h>

typedef struct {
  GMainLoop *loop;
  XdpPortal *portal;
  XdpSession *session;
  const char *frame_path;
  const char *screenshot_path;
  int pending;
  int failed;
} App;

static void complete(App *app, int success) {
  if (!success) app->failed = 1;
  if (--app->pending == 0) g_main_loop_quit(app->loop);
}

static void screenshot_ready(GObject *source, GAsyncResult *result, gpointer data) {
  App *app = data;
  GError *error = NULL;
  char *uri = xdp_portal_take_screenshot_finish(XDP_PORTAL(source), result, &error);
  if (!uri) {
    fprintf(stderr, "SCREENSHOT_FAIL %s\n", error ? error->message : "unknown");
    g_clear_error(&error);
    complete(app, 0);
    return;
  }
  char *source_path = g_filename_from_uri(uri, NULL, &error);
  gchar *bytes = NULL;
  gsize size = 0;
  gboolean copied = source_path && g_file_get_contents(source_path, &bytes, &size, &error) &&
                    g_file_set_contents(app->screenshot_path, bytes, size, &error);
  if (source_path) unlink(source_path);
  if (copied)
    fprintf(stderr, "SCREENSHOT_CONSUMED bytes=%zu\n", size);
  else
    fprintf(stderr, "SCREENSHOT_COPY_FAIL %s\n", error ? error->message : "unknown");
  g_clear_error(&error);
  g_free(bytes);
  g_free(source_path);
  g_free(uri);
  complete(app, copied);
}

static void capture_frame(App *app) {
  GVariant *streams = xdp_session_get_streams(app->session);
  GVariantIter iterator;
  guint32 node_id = 0;
  GVariant *properties = NULL;
  if (!streams) {
    fprintf(stderr, "STREAMS_FAIL none\n");
    complete(app, 0);
    return;
  }
  g_variant_iter_init(&iterator, streams);
  if (!g_variant_iter_next(&iterator, "(u@a{sv})", &node_id, &properties)) {
    fprintf(stderr, "STREAMS_FAIL empty\n");
    complete(app, 0);
    return;
  }
  gchar *text = g_variant_print(properties, TRUE);
  fprintf(stderr, "PORTAL_STREAM node_id=%u props=%s\n", node_id, text);
  g_free(text);
  g_variant_unref(properties);

  int pipewire_fd = xdp_session_open_pipewire_remote(app->session);
  if (pipewire_fd < 0) {
    fprintf(stderr, "PIPEWIRE_REMOTE_FAIL\n");
    complete(app, 0);
    return;
  }

  GError *error = NULL;
  GstElement *pipeline = gst_parse_launch(
      "pipewiresrc name=src num-buffers=1 ! video/x-raw ! filesink name=sink", &error);
  if (!pipeline || !GST_IS_BIN(pipeline)) {
    fprintf(stderr, "GST_PARSE_FAIL %s\n", error ? error->message : "not a pipeline");
    g_clear_error(&error);
    if (pipeline) gst_object_unref(pipeline);
    close(pipewire_fd);
    complete(app, 0);
    return;
  }
  GstElement *source = gst_bin_get_by_name(GST_BIN(pipeline), "src");
  GstElement *sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
  if (!source || !sink) {
    fprintf(stderr, "GST_ELEMENT_FAIL\n");
    if (source) gst_object_unref(source);
    if (sink) gst_object_unref(sink);
    gst_object_unref(pipeline);
    close(pipewire_fd);
    complete(app, 0);
    return;
  }

  char node_path[32];
  snprintf(node_path, sizeof node_path, "%u", node_id);
  g_object_set(source, "fd", pipewire_fd, "path", node_path, NULL);
  g_object_set(sink, "location", app->frame_path, NULL);
  int success = gst_element_set_state(pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE;
  GstBus *bus = gst_element_get_bus(pipeline);
  GstMessage *message = success ? gst_bus_timed_pop_filtered(
                                      bus, 20 * GST_SECOND, GST_MESSAGE_ERROR | GST_MESSAGE_EOS)
                                : NULL;
  if (!message || GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
    if (message) {
      GError *gst_error = NULL;
      gchar *debug = NULL;
      gst_message_parse_error(message, &gst_error, &debug);
      fprintf(stderr, "GSTREAMER_FAIL %s %s\n", gst_error ? gst_error->message : "unknown",
              debug ? debug : "");
      g_clear_error(&gst_error);
      g_free(debug);
    } else {
      fprintf(stderr, "GSTREAMER_FAIL timeout\n");
    }
    success = 0;
  }

  struct stat metadata;
  if (success && (stat(app->frame_path, &metadata) || metadata.st_size <= 0)) success = 0;
  if (success) {
    GstPad *pad = gst_element_get_static_pad(source, "src");
    GstCaps *caps = gst_pad_get_current_caps(pad);
    gchar *caps_text = caps ? gst_caps_to_string(caps) : g_strdup("unknown");
    fprintf(stderr, "FRAME_CONSUMED bytes=%lld caps=%s\n", (long long)metadata.st_size, caps_text);
    g_free(caps_text);
    if (caps) gst_caps_unref(caps);
    gst_object_unref(pad);
  }

  if (message) gst_message_unref(message);
  gst_object_unref(bus);
  gst_element_set_state(pipeline, GST_STATE_NULL);
  gst_object_unref(source);
  gst_object_unref(sink);
  gst_object_unref(pipeline);
  close(pipewire_fd);
  complete(app, success);
}

static void session_started(GObject *source, GAsyncResult *result, gpointer data) {
  App *app = data;
  GError *error = NULL;
  if (!xdp_session_start_finish(XDP_SESSION(source), result, &error)) {
    fprintf(stderr, "START_FAIL %s\n", error ? error->message : "unknown");
    g_clear_error(&error);
    complete(app, 0);
    return;
  }
  fprintf(stderr, "PORTAL_START ok\n");
  capture_frame(app);
}

static void session_created(GObject *source, GAsyncResult *result, gpointer data) {
  App *app = data;
  GError *error = NULL;
  app->session = xdp_portal_create_screencast_session_finish(XDP_PORTAL(source), result, &error);
  if (!app->session) {
    fprintf(stderr, "CREATE_FAIL %s\n", error ? error->message : "unknown");
    g_clear_error(&error);
    complete(app, 0);
    return;
  }
  fprintf(stderr, "PORTAL_CREATE_SELECT ok\n");
  xdp_session_start(app->session, NULL, NULL, session_started, app);
}

int main(int argc, char **argv) {
  gst_init(&argc, &argv);
  if (argc != 3) {
    fprintf(stderr, "usage: %s FRAME.raw SCREENSHOT.png\n", argv[0]);
    return 2;
  }
  App app = {.frame_path = argv[1], .screenshot_path = argv[2], .pending = 2};
  app.loop = g_main_loop_new(NULL, FALSE);
  app.portal = xdp_portal_new();
  xdp_portal_take_screenshot(app.portal, NULL, XDP_SCREENSHOT_FLAG_NONE, NULL, screenshot_ready, &app);
  xdp_portal_create_screencast_session(
      app.portal, XDP_OUTPUT_MONITOR, XDP_SCREENCAST_FLAG_NONE, XDP_CURSOR_MODE_HIDDEN,
      XDP_PERSIST_MODE_NONE, NULL, NULL, session_created, &app);
  g_main_loop_run(app.loop);
  if (app.session) {
    xdp_session_close(app.session);
    g_object_unref(app.session);
  }
  g_object_unref(app.portal);
  g_main_loop_unref(app.loop);
  return app.failed;
}
