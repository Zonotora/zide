pub const MapRequestEvent = struct {
    window: u32,
    kind: u8,
};

pub const ZideEvent = union(enum) {
    none,
    quit,
    map_request: MapRequestEvent,
    unmap_request: u32,
    unmap_notify: u32,
    enter_notify: u32,
    key_press: Action,
};

pub const Action = enum {
    none,
    quit,
    toggle,
    close_window,
    add_terminal,
};

pub const RawKeyBinding = struct {
    keysym: u16,
    mods: u16,
};

pub const KeyBinding = struct {
    keycode: u16,
    mods: u16,
};
