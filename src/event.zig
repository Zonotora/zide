pub const MapRequestEvent = struct {
    window: u32,
    kind: u8,
};

pub const ButtonEvent = struct {
    window: u32,
    x: i16,
    y: i16,
    root_x: i16,
    root_y: i16,
};

pub const ZideEvent = union(enum) {
    none,
    quit,
    map_request: MapRequestEvent,
    unmap_request: u32,
    unmap_notify: u32,
    enter_notify: u32,
    key_press: Action,
    button_press: ButtonEvent,
    button_release: ButtonEvent,
    button_motion: ButtonEvent,
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
