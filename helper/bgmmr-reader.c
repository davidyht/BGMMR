/*
 * bgmmr-reader: HSTracker sidecar. Attaches Frida to Hearthstone (pid arg), runs an
 * embedded Mono-walk agent, and prints the leaderboard "send" messages to stdout, one
 * JSON object per line, e.g.:  {"type":"send","payload":{"type":"names","names":[...]}}
 * Runs until killed (SIGTERM) or Hearthstone detaches. Reads names by name via the
 * Mono C API (no hardcoded offsets), so it survives game patches.
 */
#include "frida-core.h"
#include "agent_js.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <signal.h>

static GMainLoop *loop = NULL;

static gboolean stop(gpointer user_data) { (void) user_data; g_main_loop_quit(loop); return FALSE; }
static void on_signal(int signo) { (void) signo; g_idle_add(stop, NULL); }

static void on_detached(FridaSession *session, FridaSessionDetachReason reason,
                        FridaCrash *crash, gpointer user_data) {
    (void) session; (void) reason; (void) crash; (void) user_data;
    fprintf(stderr, "bgmmr: detached\n");
    g_idle_add(stop, NULL);
}

static void on_message(FridaScript *script, const gchar *message, GBytes *data, gpointer user_data) {
    (void) script; (void) data; (void) user_data;
    JsonParser *parser = json_parser_new();
    if (json_parser_load_from_data(parser, message, -1, NULL)) {
        JsonObject *root = json_node_get_object(json_parser_get_root(parser));
        const gchar *type = json_object_has_member(root, "type")
            ? json_object_get_string_member(root, "type") : NULL;
        if (type != NULL && strcmp(type, "send") == 0) {
            printf("%s\n", message);
            fflush(stdout);
        } else {
            fprintf(stderr, "bgmmr-js: %s\n", message);
        }
    }
    g_object_unref(parser);
}

int main(int argc, char *argv[]) {
    guint target_pid;
    GError *error = NULL;

    frida_init();
    if (argc != 2 || (target_pid = atoi(argv[1])) == 0) {
        g_printerr("usage: %s <hearthstone-pid>\n", argv[0]);
        return 1;
    }

    loop = g_main_loop_new(NULL, TRUE);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    FridaDeviceManager *manager = frida_device_manager_new();
    FridaDevice *device = frida_device_manager_get_device_by_type_sync(
        manager, FRIDA_DEVICE_TYPE_LOCAL, 1, NULL, &error);
    if (error != NULL) {
        g_printerr("bgmmr: no local device: %s\n", error->message);
        return 2;
    }

    FridaSession *session = frida_device_attach_sync(device, target_pid, NULL, NULL, &error);
    if (error != NULL) {
        g_printerr("bgmmr: attach failed: %s\n", error->message);
        return 3;
    }
    g_signal_connect(session, "detached", G_CALLBACK(on_detached), NULL);

    char *src = (char *) malloc(bgmmr_agent_js_len + 1);
    memcpy(src, bgmmr_agent_js, bgmmr_agent_js_len);
    src[bgmmr_agent_js_len] = '\0';

    FridaScriptOptions *options = frida_script_options_new();
    frida_script_options_set_name(options, "bgmmr");
    frida_script_options_set_runtime(options, FRIDA_SCRIPT_RUNTIME_QJS);

    FridaScript *script = frida_session_create_script_sync(session, src, options, NULL, &error);
    free(src);
    g_clear_object(&options);
    if (error != NULL) {
        g_printerr("bgmmr: create script failed: %s\n", error->message);
        return 4;
    }
    g_signal_connect(script, "message", G_CALLBACK(on_message), NULL);

    frida_script_load_sync(script, NULL, &error);
    if (error != NULL) {
        g_printerr("bgmmr: load failed: %s\n", error->message);
        return 5;
    }
    fprintf(stderr, "bgmmr: attached to %u, streaming names\n", target_pid);

    g_main_loop_run(loop);

    frida_script_unload_sync(script, NULL, NULL);
    frida_unref(script);
    frida_session_detach_sync(session, NULL, NULL);
    frida_unref(session);
    frida_unref(device);
    frida_device_manager_close_sync(manager, NULL, NULL);
    frida_unref(manager);
    g_main_loop_unref(loop);
    return 0;
}
