const std = @import("std");

const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
});

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();

    var children = try std.ArrayList(*std.process.Child).initCapacity(allocator, 10);
    defer children.deinit(allocator);

    // Open log file
    const log_file = c.fopen("/tmp/zide-debug.log", "w");
    defer _ = c.fclose(log_file);
    _ = c.fprintf(log_file, "=== ZIDE STARTING ===\n");
    _ = c.fflush(log_file);

    var screen_num: c_int = 0;
    const connection = c.xcb_connect(null, &screen_num);
    defer c.xcb_disconnect(connection);

    // Check if connection failed
    const conn_error = c.xcb_connection_has_error(connection);
    _ = c.fprintf(log_file, "Connection error code: %d\n", conn_error);
    _ = c.fflush(log_file);
    if (conn_error != 0) {
        std.debug.print("Failed to connect to X server: error code {}\n", .{conn_error});
        _ = c.fprintf(log_file, "FAILED: Connection error\n");
        _ = c.fflush(log_file);
        return error.ConnectionFailed;
    }

    const setup = c.xcb_get_setup(connection);
    const iter = c.xcb_setup_roots_iterator(setup);
    const screen: [*c]c.xcb_screen_t = iter.data;

    if (screen == null) {
        std.debug.print("Failed to get screen\n", .{});
        return error.NoScreen;
    }

    std.debug.print("connection: {any} screen_num={}\n", .{ connection, screen_num });
    std.debug.print("screen={}\n", .{screen.*});
    _ = c.fflush(c.stderr);

    // c.xcb_setup
    const mask: u32 = c.XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT |
        c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
        c.XCB_EVENT_MASK_ENTER_WINDOW;

    const mask_values = [_]u32{mask};

    const root = screen.*.root;
    const cookie = c.xcb_change_window_attributes(connection, root, c.XCB_CW_EVENT_MASK, &mask_values);

    const err = c.xcb_request_check(connection, cookie);
    if (err != null) {
        std.debug.print("Error setting up window manager: error code {}\n", .{err.*.error_code});
        std.debug.print("Another window manager may already be running.\n", .{});
        return error.WindowManagerAlreadyRunning;
    }
    _ = c.xcb_grab_button(
        connection,
        0, // owner_events = false (we get the events)
        root,
        c.XCB_EVENT_MASK_BUTTON_PRESS | c.XCB_EVENT_MASK_BUTTON_RELEASE,
        c.XCB_GRAB_MODE_ASYNC, // pointer_mode
        c.XCB_GRAB_MODE_ASYNC, // keyboard_mode
        c.XCB_NONE, // confine_to
        c.XCB_NONE, // cursor
        c.XCB_BUTTON_INDEX_ANY, // button
        c.XCB_MOD_MASK_ANY, // modifiers (any modifier keys)
    );

    _ = c.xcb_get_keyboard_mapping(connection, setup.*.min_keycode, setup.*.max_keycode - setup.*.min_keycode + 1);

    // 24 | q
    // 38 | a
    _ = c.xcb_grab_key(connection, 1, root, c.XCB_MOD_MASK_ANY, 24, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
    // const mod_key =
    _ = c.xcb_grab_key(connection, 1, root, c.XCB_MOD_MASK_ANY, 38, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);

    std.debug.print("Window manager started successfully\n", .{});
    _ = c.fflush(c.stderr);
    _ = c.fprintf(log_file, "=== WM STARTED - ENTERING EVENT LOOP ===\n");
    _ = c.fflush(log_file);

    var is_running: bool = true;
    while (is_running) {
        _ = c.xcb_flush(connection);

        const event = c.xcb_wait_for_event(connection);
        if (event == null) {
            std.debug.print("Connection to X server lost\n", .{});
            break;
        }
        defer c.free(event);

        const response_type = event.*.response_type & ~@as(u8, 0x80);

        // Event type 0 means it's an error
        if (response_type == 0) {
            const error_event: [*c]c.xcb_generic_error_t = @ptrCast(@alignCast(event));
            std.debug.print("X Error: error_code={} major_code={} minor_code={}\n", .{
                error_event.*.error_code,
                error_event.*.major_code,
                error_event.*.minor_code,
            });
            continue;
        }

        _ = c.fprintf(log_file, "event %d\n", response_type);
        _ = c.fflush(log_file);

        // Handle events
        switch (response_type) {
            c.XCB_MAP_REQUEST => {
                const map_event: [*c]c.xcb_map_request_event_t = @ptrCast(event);

                // Don't include BUTTON_PRESS in the event mask - we'll grab buttons instead
                const event_mask =
                    c.XCB_EVENT_MASK_EXPOSURE |
                    c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
                    c.XCB_EVENT_MASK_ENTER_WINDOW;

                _ = c.xcb_change_window_attributes(connection, map_event.*.window, c.XCB_CW_EVENT_MASK, &event_mask);

                // Grab mouse buttons to receive clicks without breaking enter/leave events
                // XCB_BUTTON_INDEX_ANY means all buttons
                // _ = c.xcb_grab_button(
                //     connection,
                //     0, // owner_events = false (we get the events)
                //     map_event.*.window,
                //     c.XCB_EVENT_MASK_BUTTON_PRESS | c.XCB_EVENT_MASK_BUTTON_RELEASE,
                //     c.XCB_GRAB_MODE_ASYNC, // pointer_mode
                //     c.XCB_GRAB_MODE_ASYNC, // keyboard_mode
                //     c.XCB_NONE, // confine_to
                //     c.XCB_NONE, // cursor
                //     c.XCB_BUTTON_INDEX_ANY, // button
                //     c.XCB_MOD_MASK_ANY, // modifiers (any modifier keys)
                // );

                _ = c.xcb_map_window(connection, map_event.*.window);
                _ = c.fprintf(log_file, "map_request window=%d parent=%d\n", map_event.*.window, map_event.*.parent);
            },
            c.XCB_BUTTON_PRESS => {
                _ = c.fprintf(log_file, "Button press event\n");
            },
            c.XCB_KEY_PRESS => {
                const key_event: [*c]c.xcb_key_press_event_t = @ptrCast(event);
                _ = c.fprintf(log_file, "Key press event: %d\n", key_event.*.detail);
                const key = key_event.*.detail;
                // c.xcb_get_keyboard_mapping(c: ?*struct_xcb_connection_t, first_keycode: u8, count: u8)
                // is_running = false;
                if (key == 24) {
                    is_running = false;
                } else if (key == 38) {
                    const args = .{"alacritty"};
                    var child = std.process.Child.init(&args, allocator);
                    // defer child.dein
                    try child.spawn();
                    try children.append(allocator, &child);
                }

                // if (key_event.*.detail == 0) {

                // }
            },
            c.XCB_MOTION_NOTIFY => {

                // const window =
                // c.xcb_set_input_focus(connection, 1, window, 0);
            },
            c.XCB_ENTER_NOTIFY => {
                const notify_event: [*c]c.xcb_enter_notify_event_t = @ptrCast(event);
                const window = notify_event.*.event;
                _ = c.xcb_set_input_focus(connection, c.XCB_INPUT_FOCUS_POINTER_ROOT, window, c.XCB_CURRENT_TIME);
                _ = c.fprintf(log_file, "enter_notify event=%d root=%d\n", notify_event.*.event, notify_event.*.root);
            },
            else => {},
        }
        _ = c.fflush(log_file);
    }

    for (children.items) |child| {
        _ = try child.kill();
    }
}
