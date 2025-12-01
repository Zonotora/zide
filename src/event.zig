pub const MapRequestEvent = struct {
    window: u32,
    kind: u8,
};

pub const ZideEvent = union(enum) {
    none,
    quit,
    toggle,
    map_request: MapRequestEvent,
    enter_notify: u32,
};
