const std = @import("std");
const Allocator = std.mem.Allocator;

const MapRequestEvent = @import("event.zig").MapRequestEvent;

const Rect = struct {
    x: i16 = 100,
    y: i16 = 100,
    width: u16 = 800,
    height: u16 = 600,
};

const Orientation = enum {
    horizontal,
    vertical,
};

pub const Window = struct {
    window: u32,
    kind: u8,
    rect: Rect = .{},
    orientation_hint: Orientation = .horizontal,
    floating: bool = false,

    const Self = @This();

    pub fn init(window: u32, kind: u8) Self {
        return .{
            .window = window,
            .kind = kind,
        };
    }
};

const Node = struct {
    parent: ?*Node,
    value: union(enum) {
        window: *Window,
        tree: Tree,
    },
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
        // const tree = w.tree;
        // remove_focus = tree.remove(window);
        // const is_top_tree = &self.tree == tree;
        // // Remove tree
        // if (!is_top_tree and tree.nodes.items.len == 0) {}
        // // Remove tree and replace with node
        // else if (!is_top_tree and tree.nodes.items.len == 1) {}

        if (self.findWindowIndex(target)) |index| {
            // Remove node
            _ = self.nodes.swapRemove(index);

            // If there are no nodes left in the tree, remove the tree

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

const TreeView = struct {
    root: Tree,
    focus: ?*Node,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        // .root_tree = Node{ .parent = null, .value = .{
        //     .tree = try Tree.init(allocator),
        // } },
        return .{
            .root = Tree.init(allocator),
            .focus = null,
        };
    }

    pub fn deinit(self: Self) void {
        self.root.deinit();
    }

    pub fn add(self: Self, window: *Window) void {
        _ = self;
        _ = window;
        // if (self.focus == null) {
        //     const window = Window{ .window = event.window, .kind = event.kind, .rect = .{} };
        //     // TODO: error union
        //     self.windows.append(self.allocator, window) catch {};
        //     const last = self.windows.items.len - 1;

        //     self.root_tree.value.tree.insert(null, Node{ .parent = &self.root_tree, .value = .{ .window = &self.windows.items[last] } });

        //     std.debug.print("window={}", .{window});

        //     self.focus = &self.windows.items[last];
        // } else {
        //     // const parent = self.focus.?.;
        //     const tree = parent.value.tree;
        //     // const tree = self.focus.?.tree;
        //     // std.debug.print("focus={}\n", .{self.focus.?.window});

        //     const window = Window{ .tree = tree, .window = event.window, .kind = event.kind, .rect = .{}, .orientation_hint = tree.orientation };
        //     // TODO: error union
        //     self.windows.append(self.allocator, window) catch {};
        //     const last = self.windows.items.len - 1;

        //     // Insert new tree node
        //     if (self.focus.?.orientation_hint != tree.orientation) {
        //         var orth_tree = try Tree.init(self.allocator);
        //         const parent_node = Node{ .parent = parent, .value = .{ .tree = orth_tree } };

        //         orth_tree.orientation = self.focus.?.orientation_hint;
        //         orth_tree.insertWithIndex(0, Node{ .parent = parent_node, .value = .{ .window = self.focus.? } });

        //         const prev_focus = tree.remove(self.focus.?.window);
        //         orth_tree.insertWithIndex(1, Node{ .window = &self.windows.items[last] });
        //         // TODO: What if prev_focus is null?
        //         tree.insertWithIndex(prev_focus.?, Node{ .tree = orth_tree });
        //         tree.print(.{});

        //         std.debug.print("prev_focus={?}\n", .{prev_focus});
        //         const tree_ptr = if (prev_focus == null)
        //             &tree.nodes.items[0].tree
        //         else
        //             &tree.nodes.items[@intCast(prev_focus.?)].tree;
        //         for (orth_tree.nodes.items) |n| {
        //             n.window.tree = tree_ptr;
        //             n.window.orientation_hint = orth_tree.orientation;
        //         }

        //         std.debug.print("different orientation focus={?} {}\n", .{ prev_focus, self.focus.?.window });
        //         self.focus.?.tree.print(.{});
        //         std.debug.print("1", .{});
        //     } else {
        //         tree.insert(self.focus.?.window, Node{ .window = &self.windows.items[last] });
        //     }

        //     // update nodes in tree
        //     tree.update();
        //     tree.print(.{});

        //     std.debug.print("tree={}", .{tree});

        //     // Set focus
        //     self.focus = &self.windows.items[last];
        // }
    }

    pub fn remove(self: Self, window_id: u32) ?u32 {
        _ = self;
        _ = window_id;
        return null;
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
};

const FloatingView = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn view(self: *Self) View {
        return View{
            .ptr = self,
            .vtable = &.{
                .deinit = deinit,
                .add = add,
                .remove = remove,
            },
        };
    }

    pub fn deinit(_: *anyopaque) void {}

    pub fn add(_: *anyopaque, window: *Window) void {
        window.floating = true;
    }
    pub fn remove(_: *anyopaque, window_id: u32) void {
        // window.floating = false;
        _ = window_id;
    }
};

const View = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const Self = @This();

    const VTable = struct {
        deinit: *const fn (ptr: *anyopaque) void,
        add: *const fn (ptr: *anyopaque, window: *Window) void,
        remove: *const fn (ptr: *anyopaque, window_id: u32) void,
    };

    pub fn deinit(self: Self) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn add(self: Self, window: *Window) void {
        return self.vtable.add(self.ptr, window);
    }

    pub fn remove(self: Self, window_id: u32) void {
        return self.vtable.remove(self.ptr, window_id);
    }
};

const ViewImpl = union {
    floating: FloatingView,
};

const Movable = struct {
    window: ?*Window = null,
    x: i16 = 0,
    y: i16 = 0,
};

pub const Workspace = struct {
    allocator: Allocator,
    windows: std.ArrayList(Window),
    rect: Rect,
    view_impl: *ViewImpl,
    view: View,
    movable: Movable,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const view_impl = try allocator.create(ViewImpl);
        view_impl.*.floating = FloatingView.init();
        const view = view_impl.floating.view();

        return .{
            .allocator = allocator,
            .windows = try std.ArrayList(Window).initCapacity(allocator, 10),
            .rect = .{},
            .view_impl = view_impl,
            .view = view,
            .movable = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.view.deinit();
        self.windows.deinit(self.allocator);
    }

    pub fn add(self: *Self, event: MapRequestEvent) !void {
        self.windows.append(self.allocator, Window.init(event.window, event.kind)) catch {};

        const last = self.windows.items.len - 1;
        self.view.add(&self.windows.items[last]);

        std.debug.print("workspace_add event={}\n", .{event});
    }

    // TODO: Function signature
    pub fn remove(self: *Self, window: u32) ?u32 {
        std.debug.print("remove window={}\n", .{window});
        var remove_index: ?usize = null;
        for (self.windows.items, 0..) |w, index| {
            if (w.window == window) {
                remove_index = index;
                break;
            }
        }

        const remove_focus: ?u32 = null;
        if (remove_index) |index| {
            const window_id = self.windows.items[index].window;
            self.view.remove(window_id);
            _ = self.windows.swapRemove(index);
        }

        return remove_focus;
    }

    // pub fn removeFocused(self: *Self) ?u32 {
    //     if (self.view.focus) |focus| {
    //         return self.remove(focus.window);
    //     }
    //     return null;
    // }

    pub fn setFocus(self: *Self, target: u32) void {
        _ = self;
        _ = target;
        // for (self.windows.items, 0..) |w, index| {
        //     if (w.window == target) {
        //         self.focus = &self.windows.items[index];
        //         break;
        //     }
        // }
    }

    pub fn setMovable(self: *Self, window_id: u32, x: i16, y: i16, set: bool) void {
        if (!set) {
            self.movable = .{};
            return;
        }

        for (self.windows.items) |*window| {
            if (window.window == window_id) {
                if (window.floating) {
                    self.movable = .{ .window = window, .x = x, .y = y };
                }
                return;
            }
        }
    }

    pub fn moveWindow(self: Self, window_id: u32, x: i16, y: i16) void {
        if (self.movable.window) |window| {
            if (window_id == window.window) {
                window.rect.x = x - self.movable.x;
                window.rect.y = y - self.movable.y;
            }
        }
    }
};
