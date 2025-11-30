const std = @import("std");
const Allocator = std.mem.Allocator;

const MapRequestEvent = @import("event.zig").MapRequestEvent;

pub const Window = struct {
    window: u32,
    kind: u8,
    x: u32 = 0,
    y: u32 = 0,
    width: u32 = 0,
    height: u32 = 1080,
};

pub const Workspace = struct {
    allocator: Allocator,
    windows: std.ArrayList(Window),
    // floating_windows: std.ArrayList(Window),
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .windows = try std.ArrayList(Window).initCapacity(allocator, 10),
            .x = 0,
            .y = 0,
            .width = 1920,
            .height = 1080,
        };
    }

    pub fn deinit(self: *Self) void {
        self.windows.deinit(self.allocator);
    }

    pub fn add(self: *Self, event: MapRequestEvent) void {
        self.windows.append(self.allocator, Window{ .window = event.window, .kind = event.kind }) catch {};
        std.debug.print("workspace_add event={}\n", .{event});
    }

    pub fn update(self: Self) void {
        if (self.windows.items.len == 0) {
            return;
        }
        const window_width = self.width / self.windows.items.len;

        for (self.windows.items, 0..) |*window, index| {
            window.x = @intCast(index * window_width);
            window.width = @intCast(window_width);
        }
    }
};
