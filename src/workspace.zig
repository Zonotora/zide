const std = @import("std");
const Allocator = std.mem.Allocator;

const MapRequestEvent = @import("event.zig").MapRequestEvent;

const Rect = struct {
    x: u32 = 0,
    y: u32 = 0,
    width: u32 = 1920,
    height: u32 = 1080,
};

const Orientation = enum {
    horizontal,
    vertical,
};

pub const Window = struct {
    window: u32,
    kind: u8,
    rect: Rect,
    tree: *Tree,
    orientation_hint: Orientation = .horizontal,
};

const Node = union(enum) {
    window: *Window,
    tree: Tree,
};

pub const Tree = struct {
    allocator: Allocator,
    orientation: Orientation,
    nodes: std.ArrayList(Node),
    rect: Rect,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .orientation = .horizontal,
            .nodes = try std.ArrayList(Node).initCapacity(allocator, 1),
            .rect = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node| {
            switch (node.*) {
                .tree => |*t| {
                    t.deinit();
                },
                else => {},
            }
        }

        self.nodes.deinit(self.allocator);
    }

    fn findWindowIndex(self: Self, target: u32) ?usize {
        var target_index: ?usize = null;

        for (self.nodes.items, 0..) |n, index| {
            switch (n) {
                .window => |w| {
                    if (target == w.window) {
                        target_index = index;
                    }
                },
                .tree => {},
            }
        }
        return target_index;
    }

    pub fn insert(self: *Self, focus: ?u32, node: Node) void {
        if (focus == null) {
            // TODO: error union
            self.nodes.insert(self.allocator, 0, node) catch {};
        } else {
            const target_index = self.findWindowIndex(focus.?);

            if (target_index == null) {
                // TODO: error union
                self.nodes.append(self.allocator, node) catch {};
            } else {
                // TODO: error union
                self.nodes.insert(self.allocator, @intCast(target_index.?), node) catch {};
            }
        }
    }

    pub fn remove(self: *Self, target: u32) ?u32 {
        if (self.findWindowIndex(target)) |index| {
            _ = self.nodes.swapRemove(index);
            if (index == 0) {
                return null;
            }
            var i: usize = index - 1;
            while (i > 0) : (i -= 1) {
                switch (self.nodes.items[i]) {
                    .window => |w| {
                        return w.window;
                    },
                    else => {},
                }
            }
        }
        return null;
    }

    fn updatePosition(self: Self, rect: *Rect, index: u32) void {
        switch (self.orientation) {
            .horizontal => {
                const width: u32 = @intCast(self.rect.width / self.nodes.items.len);
                rect.x = index * width;
                rect.y = self.rect.y;
                rect.width = width;
                rect.height = self.rect.height;
            },
            .vertical => {
                const height: u32 = @intCast(self.rect.height / self.nodes.items.len);
                rect.x = self.rect.y;
                rect.y = index * height;
                rect.width = self.rect.width;
                rect.height = height;
            },
        }
    }

    pub fn update(self: Self) void {
        for (self.nodes.items, 0..) |*node, index| {
            switch (node.*) {
                .window => |w| self.updatePosition(&w.rect, @intCast(index)),
                .tree => |*t| {
                    self.updatePosition(&t.rect, @intCast(index));
                    t.update();
                },
            }
        }
    }
};

pub const Workspace = struct {
    allocator: Allocator,
    tree: Tree,
    windows: std.ArrayList(Window),
    // floating_windows: std.ArrayList(Window),
    rect: Rect,
    focus: ?*Window,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return .{
            .allocator = allocator,
            .tree = try Tree.init(allocator),
            .windows = try std.ArrayList(Window).initCapacity(allocator, 10),
            .rect = .{},
            .focus = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tree.deinit();
        self.windows.deinit(self.allocator);
    }

    pub fn add(self: *Self, event: MapRequestEvent) !void {
        if (self.focus == null) {
            const window = Window{ .tree = &self.tree, .window = event.window, .kind = event.kind, .rect = .{} };
            // TODO: error union
            self.windows.append(self.allocator, window) catch {};
            const last = self.windows.items.len - 1;
            self.tree.insert(null, Node{ .window = &self.windows.items[last] });
            std.debug.print("window={}", .{window});

            self.focus = &self.windows.items[last];
        } else {
            const tree = self.focus.?.tree;
            const window = Window{ .tree = tree, .window = event.window, .kind = event.kind, .rect = .{} };
            // TODO: error union
            self.windows.append(self.allocator, window) catch {};
            const last = self.windows.items.len - 1;

            // Insert new tree node
            if (self.focus.?.orientation_hint != tree.orientation) {
                var orth_tree = try Tree.init(self.allocator);
                orth_tree.orientation = self.focus.?.orientation_hint;
                orth_tree.insert(null, Node{ .window = self.focus.? });
                const prev_focus = tree.remove(self.focus.?.window);
                orth_tree.insert(self.focus.?.window, Node{ .window = &self.windows.items[last] });
                tree.insert(prev_focus, Node{ .tree = orth_tree });
            } else {
                tree.insert(self.focus.?.window, Node{ .window = &self.windows.items[last] });
            }

            // update nodes in tree
            tree.update();

            std.debug.print("tree={}", .{tree});

            // Set focus
            self.focus = &self.windows.items[last];
        }

        std.debug.print("workspace_add event={}\n", .{event});
    }

    pub fn toggle(self: *Self) void {
        if (self.focus == null) {
            return;
        }

        switch (self.focus.?.orientation_hint) {
            .horizontal => self.focus.?.orientation_hint = .vertical,
            .vertical => self.focus.?.orientation_hint = .horizontal,
        }
    }

    pub fn update(self: Self) void {
        _ = self;
        // if (self.windows.items.len == 0) {
        //     return;
        // }
        // for (self.windows.items, 0..) |*window, index| {
        //     const parent = window.container.rect;
        //     const n_windows = @max(window.container.n_windows, 1);

        //     switch (window.container.orientation) {
        //         .horizontal => {
        //             const size = parent.width / n_windows;
        //             window.x = parent.x + size;
        //             window.y = parent.y;
        //             window.width = @intCast();
        //             window.height = parent.height;
        //         },
        //         .vertical => {
        //             window.x = parent.x + 0;
        //             window.width = @intCast(window_width);
        //         },
        //     }
        // }
    }
};
