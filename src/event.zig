pub const MapRequestEvent = struct {
    window: u32,
    kind: u8,
};

pub const ZineEvent = union(enum) {
    none,
    quit,
    toggle,
    map_request: MapRequestEvent,
};
