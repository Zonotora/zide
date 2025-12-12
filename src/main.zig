const std = @import("std");

const x = @import("x.zig");
const Workspace = @import("workspace.zig").Workspace;
const c = x.c;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();

    var children = try std.ArrayList(*std.process.Child).initCapacity(allocator, 10);
    defer children.deinit(allocator);

    const conn = try x.Connection.init(allocator);
    defer conn.deinit();
    const connection = conn.connection;

    var workspace = try Workspace.init(allocator);
    defer workspace.deinit();

    std.debug.print("zide starting", .{});
    // Check if connection failed

    var is_running: bool = true;
    while (is_running) {
        _ = c.xcb_flush(connection);

        const event = c.xcb_wait_for_event(connection);
        if (event == null) {
            std.debug.print("Connection to X server lost\n", .{});
            break;
        }
        defer c.free(event);

        switch (try conn.processEvent(event)) {
            .none => {},
            .quit => is_running = false,
            .map_request => |e| {
                try workspace.add(e);
            },
            .unmap_notify, .unmap_request => |w| {
                try workspace.remove(w);
            },
            .enter_notify => |w| {
                workspace.setFocus(w);
            },
            .key_press => |action| {
                switch (action) {
                    .none => {},
                    .quit => is_running = false,
                    .toggle => {
                        workspace.toggle();
                    },
                    .close_window => {},
                    .add_terminal => {
                        const args = .{"alacritty"};
                        var child = std.process.Child.init(&args, allocator);
                        // defer child.dein
                        try child.spawn();
                        try children.append(allocator, &child);
                    },
                }
            },
            // else => {}
        }

        workspace.update();

        conn.update(workspace.windows);
    }

    for (children.items) |child| {
        _ = try child.kill();
    }
}
