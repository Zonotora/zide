const std = @import("std");

const xcb = @import("x.zig");
const c = xcb.c;

pub fn main() void {
    // var allocator = std.heap.page_allocator;

    // Connect to X server
    const conn = c.xcb_connect(null, null);
    if (c.xcb_connection_has_error(conn) != 0) {
        std.debug.print("Failed to connect to X server\n", .{});
        return;
    }

    const setup = c.xcb_get_setup(conn);
    const iter = c.xcb_setup_roots_iterator(setup);
    const screen = iter.data;

    // Create a window
    const wid = c.xcb_generate_id(conn);
    const values_mask = c.XCB_CW_BACK_PIXEL | c.XCB_CW_EVENT_MASK;
    var values: [2]u32 = .{
        screen.*.black_pixel,
        c.XCB_EVENT_MASK_EXPOSURE | c.XCB_EVENT_MASK_BUTTON_PRESS,
    };

    _ = c.xcb_create_window(
        conn,
        c.XCB_COPY_FROM_PARENT,
        wid,
        screen.*.root,
        100,
        100,
        400,
        300,
        0,
        c.XCB_WINDOW_CLASS_INPUT_OUTPUT,
        screen.*.root_visual,
        values_mask,
        &values[0],
    );

    // Map the window (show it)
    set_hints(conn, screen, wid);
    _ = c.xcb_map_window(conn, wid);
    _ = c.xcb_flush(conn);

    // Check X Shape extension support (optional)
    const cookie = c.xcb_shape_query_version(conn);
    const reply = c.xcb_shape_query_version_reply(conn, cookie, null);
    if (reply == null or reply.*.major_version == 0) {
        std.debug.print("X Shape extension not supported\n", .{});
        return;
    }

    // Create 1-bit depth pixmap mask for shape
    const mask_pixmap = c.xcb_generate_id(conn);
    _ = c.xcb_create_pixmap(conn, 1, mask_pixmap, wid, 400, 300);

    // Create graphics context for mask drawing
    const gc = c.xcb_generate_id(conn);
    var gc_values: [2]u32 = .{ 1, 0 }; // foreground white (1), no graphics exposures (0)
    _ = c.xcb_create_gc(conn, gc, mask_pixmap, c.XCB_GC_FOREGROUND | c.XCB_GC_GRAPHICS_EXPOSURES, &gc_values[0]);

    var event_ptr: [*c]c.xcb_generic_event_t = null;

    while (true) {
        event_ptr = c.xcb_wait_for_event(conn);
        if (event_ptr == null) {
            break;
        }
        const response_type = event_ptr.*.response_type & ~@as(u8, 0x80);
        if (response_type == c.XCB_EXPOSE) {
            // Clear mask pixmap (black = transparent)
            var rect = c.xcb_rectangle_t{ .x = 0, .y = 0, .width = 400, .height = 300 };
            _ = c.xcb_poly_fill_rectangle(conn, mask_pixmap, gc, 1, &rect);

            const x = 50;
            const y = 50;
            const width = 300;
            const height = 200;
            const r = 20; // corner radius

            // Fill rectangles to cover central parts
            var rects = [_]c.xcb_rectangle_t{ .{ .x = x + r, .y = y, .width = width - r * 2, .height = height }, .{ .x = x, .y = y + r, .width = width, .height = height - r * 2 } };
            _ = c.xcb_poly_fill_rectangle(conn, mask_pixmap, gc, @intCast(rects.len), &rects[0]);

            // Fill corner arcs for rounded corners
            var arcs = [_]c.xcb_arc_t{
                .{ .x = x, .y = y, .width = r * 2, .height = r * 2, .angle1 = 90 * 64, .angle2 = 90 * 64 },
                .{ .x = x + width - r * 2, .y = y, .width = r * 2, .height = r * 2, .angle1 = 0 * 64, .angle2 = 90 * 64 },
                .{ .x = x, .y = y + height - r * 2, .width = r * 2, .height = r * 2, .angle1 = 180 * 64, .angle2 = 90 * 64 },
                .{ .x = x + width - r * 2, .y = y + height - r * 2, .width = r * 2, .height = r * 2, .angle1 = 270 * 64, .angle2 = 90 * 64 },
            };
            _ = c.xcb_poly_fill_arc(conn, mask_pixmap, gc, @intCast(arcs.len), &arcs[0]);

            _ = c.xcb_flush(conn);

            // Apply mask to window bounding shape (clip window shape)
            _ = c.xcb_shape_mask(conn, c.XCB_SHAPE_SO_SET, c.XCB_SHAPE_SK_BOUNDING, wid, 0, 0, mask_pixmap);

            _ = c.xcb_flush(conn);
        } else if (response_type == c.XCB_BUTTON_PRESS) {
            // Exit on key press
            break;
        }
        _ = c.free(event_ptr);
    }

    std.debug.print("Exiting", .{});

    // Clean up resources
    _ = c.xcb_free_gc(conn, gc);
    _ = c.xcb_free_pixmap(conn, mask_pixmap);
    _ = c.xcb_destroy_window(conn, wid);
    _ = c.xcb_disconnect(conn);
}

const xcb_xwm_hints = extern struct {
    flags: i64 = 0,
    input: bool = false,
    initial_state: i32 = 0,
    icon_pixmap: c.xcb_pixmap_t = 0,
    icon_window: u32 = 0,
    icon_x: i32 = 0,
    icon_y: i32 = 0,
    icon_mask: c.xcb_pixmap_t = 0,
    window_group: i32 = 0,
};

fn set_hints(conn: ?*c.xcb_connection_t, screen: [*c]c.xcb_screen_t, wid: u32) void {
    // 1. Set _NET_WM_WINDOW_TYPE = _NET_WM_WINDOW_TYPE_DOCK (EWMH hint)
    const type_str = "_NET_WM_WINDOW_TYPE";
    const dock_str = "_NET_WM_WINDOW_TYPE_DOCK";
    const task_str = "_NET_WM_WINDOW_TYPE_SKIP_TASKBAR";
    const net_wm_window_type_atom = c.xcb_intern_atom(conn, 0, type_str.len, type_str);
    const net_wm_window_type_dock_atom = c.xcb_intern_atom(conn, 0, dock_str.len, dock_str);

    // Wait for replies
    const type_reply = c.xcb_intern_atom_reply(conn, net_wm_window_type_atom, null);
    const dock_reply = c.xcb_intern_atom_reply(conn, net_wm_window_type_dock_atom, null);
    defer c.free(type_reply);
    defer c.free(dock_reply);

    var dock_type_atoms: [1]c.xcb_atom_t = .{dock_reply.*.atom};
    _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, wid, type_reply.*.atom, c.XCB_ATOM_ATOM, 32, 1, &dock_type_atoms[0]);

    // 2. Set WM_HINTS for dock (no decorations, always on top, sticky)
    var wm_hints: xcb_xwm_hints = .{
        .flags = (1 << 1) | (1 << 6) | (1 << 8),
        .initial_state = 1,
        .input = false,
    };
    _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, wid, c.XCB_ATOM_WM_HINTS, c.XCB_ATOM_WM_HINTS, 32, @sizeOf(xcb_xwm_hints), &wm_hints);

    // 3. Optional: Skip taskbar (desktop/panel hint)
    const net_wm_window_type_skip_taskbar_atom = c.xcb_intern_atom(conn, 0, task_str.len, task_str);
    const skip_reply = c.xcb_intern_atom_reply(conn, net_wm_window_type_skip_taskbar_atom, null);
    defer c.free(skip_reply);
    var skip_atoms: [1]c.xcb_atom_t = .{skip_reply.*.atom};
    _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_APPEND, wid, type_reply.*.atom, c.XCB_ATOM_ATOM, 32, 1, &skip_atoms[0]);

    // 4. Position at screen edge (e.g., bottom dock)
    _ = c.xcb_configure_window(conn, wid, c.XCB_CONFIG_WINDOW_X | c.XCB_CONFIG_WINDOW_Y, &[_]u32{ screen.*.width_in_pixels - 400, screen.*.height_in_pixels - 40 });
}
