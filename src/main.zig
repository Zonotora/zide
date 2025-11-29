const std = @import("std");
const zon = @import("zon");

const c = @cImport({
    @cInclude("xcb/xcb.h");
});

pub fn main() !void {
    var screen_num: c_int = 0;
    const connection = c.xcb_connect(null, &screen_num);
    defer c.xcb_disconnect(connection);

    const setup = c.xcb_get_setup(connection);
    const iter = c.xcb_setup_roots_iterator(setup);

    const screen: [*c]c.xcb_screen_t = iter.data;

    std.debug.print("connection: {any} screen_num={}\n", .{ connection, screen_num });
    std.debug.print("screen={}\n", .{screen.*});
}
