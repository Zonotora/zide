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

    pub fn print(self: Self, options: struct { indent: u32 = 0 }) void {
        for (0..options.indent) |_| {
            std.debug.print("\t", .{});
        }
        std.debug.print("tree ({})\n", .{self.rect});
        for (self.nodes.items) |n| {
            switch (n) {
                .window => |w| {
                    for (0..options.indent) |_| {
                        std.debug.print("\t", .{});
                    }
                    std.debug.print("\tnode {} ({}) \n", .{ w.window, w.rect });
                },
                .tree => |t| t.print(.{ .indent = options.indent + 1 }),
            }
        }
    }

    fn findWindowIndex(self: Self, target: ?u32) ?usize {
        var target_index: ?usize = null;

        if (target == null) {
            return null;
        }

        for (self.nodes.items, 0..) |n, index| {
            switch (n) {
                .window => |w| {
                    if (target.? == w.window) {
                        target_index = index;
                    }
                },
                .tree => {},
            }
        }
        return target_index;
    }

    pub fn insert(self: *Self, focus: ?u32, node: Node) void {
        const target_index = self.findWindowIndex(focus);

        if (target_index == null) {
            // TODO: error union
            self.nodes.append(self.allocator, node) catch {};
        } else {
            // TODO: error union
            self.nodes.insert(self.allocator, @intCast(target_index.? + 1), node) catch {};
        }
    }

    pub fn insertWithIndex(self: *Self, index: u32, node: Node) void {
        // TODO: error union
        self.nodes.insert(self.allocator, index, node) catch {};
    }

    pub fn remove(self: *Self, target: u32) ?u32 {
        if (self.findWindowIndex(target)) |index| {
            _ = self.nodes.swapRemove(index);
            return @intCast(index);
        }
        return null;
    }

    fn updatePosition(self: Self, rect: *Rect, index: u32) void {
        switch (self.orientation) {
            .horizontal => {
                const width: u32 = @intCast(self.rect.width / self.nodes.items.len);
                rect.x = self.rect.x + index * width;
                rect.y = self.rect.y;
                rect.width = width;
                rect.height = self.rect.height;
            },
            .vertical => {
                const height: u32 = @intCast(self.rect.height / self.nodes.items.len);
                rect.x = self.rect.x;
                rect.y = self.rect.y + index * height;
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
            tree.print(.{});
            std.debug.print("focus={}\n", .{self.focus.?.window});

            const window = Window{ .tree = tree, .window = event.window, .kind = event.kind, .rect = .{}, .orientation_hint = tree.orientation };
            // TODO: error union
            self.windows.append(self.allocator, window) catch {};
            const last = self.windows.items.len - 1;

            // Insert new tree node
            if (self.focus.?.orientation_hint != tree.orientation) {
                var orth_tree = try Tree.init(self.allocator);
                orth_tree.orientation = self.focus.?.orientation_hint;
                orth_tree.insertWithIndex(0, Node{ .window = self.focus.? });
                const prev_focus = tree.remove(self.focus.?.window);
                orth_tree.insertWithIndex(1, Node{ .window = &self.windows.items[last] });
                // TODO: What if prev_focus is null?
                tree.insertWithIndex(prev_focus.?, Node{ .tree = orth_tree });
                tree.print(.{});

                std.debug.print("prev_focus={?}\n", .{prev_focus});
                const tree_ptr = if (prev_focus == null)
                    &tree.nodes.items[0].tree
                else
                    &tree.nodes.items[@intCast(prev_focus.?)].tree;
                for (orth_tree.nodes.items) |n| {
                    n.window.tree = tree_ptr;
                    n.window.orientation_hint = orth_tree.orientation;
                }

                std.debug.print("different orientation focus={?} {}\n", .{ prev_focus, self.focus.?.window });
                self.focus.?.tree.print(.{});
                std.debug.print("1", .{});
            } else {
                tree.insert(self.focus.?.window, Node{ .window = &self.windows.items[last] });
            }

            // update nodes in tree
            tree.update();
            tree.print(.{});

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

    pub fn setFocus(self: *Self, target: u32) void {
        for (self.windows.items, 0..) |w, index| {
            if (w.window == target) {
                self.focus = &self.windows.items[index];
                break;
            }
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
