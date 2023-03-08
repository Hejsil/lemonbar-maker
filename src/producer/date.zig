const datetime = @import("datetime").datetime;
const std = @import("std");

const event = std.event;

const State = @import("../main.zig").State;

pub fn date(state: *State) void {
    var next = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Copenhagen);
    next.time.second = 0;
    next.time.nanosecond = 0;

    while (true) : (std.time.sleep(std.time.ns_per_s)) {
        var now = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Copenhagen);

        if (next.lte(now)) {
            state.mutex.lock();
            state.now = now;
            state.mutex.unlock();

            next = next.shiftMinutes(1);
        }
    }
}
