const std = @import("std");
const zigmodu = @import("zigmodu");
const model = @import("model.zig");

// ── Event Types ──────────────────────────────────────────────
{{EVENT_DEFS}}

// ── Event Bus ────────────────────────────────────────────────
var event_bus: ?*zigmodu.TypedEventBus(Event) = null;

pub const Event = union(enum) {
    {{EVENT_VARIANTS}}
};

pub fn init(bus: *zigmodu.TypedEventBus(Event)) void {
    event_bus = bus;
}

pub fn publish(event: Event) void {
    if (event_bus) |bus| {
        bus.publish(event);
    }
}

// ── Subscriber ───────────────────────────────────────────────
pub const Subscriber = struct {
    pub fn subscribe(bus: *zigmodu.TypedEventBus(Event)) !void {
        {{SUBSCRIBE_CALLS}}
    }

    {{HANDLER_FUNCTIONS}}
};
