const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
});

const ZineEvent = @import("event.zig").ZineEvent;
const Window = @import("workspace.zig").Window;
const MapRequestEvent = @import("event.zig").MapRequestEvent;

pub const Connection = struct {
    allocator: Allocator,
    connection: ?*c.xcb_connection_t,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var screen_num: c_int = 0;
        const connection = c.xcb_connect(null, &screen_num);

        const conn_error = c.xcb_connection_has_error(connection);
        std.debug.print("Connection error code: {}\n", .{conn_error});
        if (conn_error != 0) {
            std.debug.print("Failed to connect to X server: error code {}\n", .{conn_error});
            std.debug.print("FAILED: Connection error\n", .{});
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
        _ = c.xcb_grab_key(connection, 1, root, c.XCB_MOD_MASK_CONTROL, 24, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
        // const mod_key =
        _ = c.xcb_grab_key(connection, 1, root, c.XCB_MOD_MASK_CONTROL, 38, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
        _ = c.xcb_grab_key(connection, 1, root, c.XCB_MOD_MASK_CONTROL, 39, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
        _ = c.xcb_grab_key(connection, 1, root, c.XCB_MOD_MASK_CONTROL, 40, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);

        std.debug.print("Window manager started successfully\n", .{});
        std.debug.print("=== WM STARTED - ENTERING EVENT LOOP ===\n", .{});

        return .{
            .allocator = allocator,
            .connection = connection,
        };
    }

    pub fn deinit(self: Self) void {
        defer c.xcb_disconnect(self.connection);
    }

    pub fn processEvent(self: Self, event: [*c]c.xcb_generic_event_t, children: *std.ArrayList(*std.process.Child)) !ZineEvent {
        const response_type = event.*.response_type & ~@as(u8, 0x80);

        // Event type 0 means it's an error
        if (response_type == 0) {
            const error_event: [*c]c.xcb_generic_error_t = @ptrCast(@alignCast(event));
            std.debug.print("X Error: error_code={} major_code={} minor_code={}\n", .{
                error_event.*.error_code,
                error_event.*.major_code,
                error_event.*.minor_code,
            });
            return .quit;
        }

        std.debug.print("event {}\n", .{response_type});

        // Handle events
        switch (response_type) {
            c.XCB_MAP_REQUEST => return self.mapRequest(@ptrCast(event)),
            c.XCB_BUTTON_PRESS => {
                std.debug.print("Button press event\n", .{});
            },
            c.XCB_KEY_PRESS => {
                const key_event: [*c]c.xcb_key_press_event_t = @ptrCast(event);
                std.debug.print("Key press event: {}\n", .{key_event.*.detail});
                const key = key_event.*.detail;
                // c.xcb_get_keyboard_mapping(c: ?*struct_xcb_connection_t, first_keycode: u8, count: u8)
                // is_running = false;
                if (key == 24) {
                    return .quit;
                } else if (key == 38) {
                    const args = .{"alacritty"};
                    var child = std.process.Child.init(&args, self.allocator);
                    // defer child.dein
                    try child.spawn();
                    try children.append(self.allocator, &child);
                } else if (key == 39) {
                    return .toggle;
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
                _ = c.xcb_set_input_focus(self.connection, c.XCB_INPUT_FOCUS_POINTER_ROOT, window, c.XCB_CURRENT_TIME);
                std.debug.print("enter_notify event={} root={}\n", .{ notify_event.*.event, notify_event.*.root });
            },
            else => {},
        }

        return .none;
    }

    pub fn mapRequest(self: Self, event: [*c]c.xcb_map_request_event_t) ZineEvent {
        if (event == null) {
            std.debug.print("map_request: event null\n", .{});
            return .none;
        }

        const window = event.*.window;
        const parent = event.*.parent;
        std.debug.print("map_request: window={} parent={}\n", .{ window, parent });

        // Don't include BUTTON_PRESS in the event mask - we'll grab buttons instead
        const event_mask =
            c.XCB_EVENT_MASK_EXPOSURE |
            c.XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY |
            c.XCB_EVENT_MASK_ENTER_WINDOW;

        // TODO: _ =
        _ = c.xcb_change_window_attributes(
            self.connection,
            window,
            c.XCB_CW_EVENT_MASK,
            &event_mask,
        );

        const cookie = c.xcb_get_geometry(self.connection, window);
        // TODO: null
        const geometry: [*c]c.xcb_get_geometry_reply_t = c.xcb_get_geometry_reply(self.connection, cookie, null);

        // geometry.*.

        _ = geometry;

        // TODO: _ =
        // _ = c.xcb_grab_server(self.connection);

        const color_mask = [_]u32{0xFFFFFF};
        _ = c.xcb_change_window_attributes(
            self.connection,
            window,
            c.XCB_CW_BORDER_PIXEL,
            &color_mask,
        );

        _ = c.xcb_configure_window(self.connection, window, c.XCB_CONFIG_WINDOW_BORDER_WIDTH, &[_]u32{1});

        const configure_mask = c.XCB_CONFIG_WINDOW_X |
            c.XCB_CONFIG_WINDOW_Y |
            c.XCB_CONFIG_WINDOW_WIDTH |
            c.XCB_CONFIG_WINDOW_HEIGHT;

        const values = [_]u32{ 50, 100, 400, 300 }; // x=50, y=100, width=400, height=300

        _ = c.xcb_configure_window(self.connection, window, configure_mask, &values);

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

        _ = c.xcb_map_window(self.connection, event.*.window);

        // TODO: Needed?
        _ = c.xcb_flush(self.connection);

        return ZineEvent{ .map_request = MapRequestEvent{ .window = window, .kind = 0 } };
    }

    pub fn update(self: Self, windows: std.ArrayList(Window)) void {
        for (windows.items) |window| {
            const configure_mask = c.XCB_CONFIG_WINDOW_X |
                c.XCB_CONFIG_WINDOW_Y |
                c.XCB_CONFIG_WINDOW_WIDTH |
                c.XCB_CONFIG_WINDOW_HEIGHT;

            const rect = window.rect;
            const values = [_]u32{ rect.x, rect.y, rect.width, rect.height };

            _ = c.xcb_configure_window(self.connection, window.window, configure_mask, &values);
        }
    }
};
