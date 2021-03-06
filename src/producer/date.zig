const datetime = @import("datetime");
const std = @import("std");

const event = std.event;

const Message = @import("../message.zig").Message;

pub fn date(channel: *event.Channel(Message)) void {
    const loop = event.Loop.instance.?;
    var next = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Copenhagen);
    next.time.second = 0;
    next.time.nanosecond = 0;

    while (true) : (loop.sleep(std.time.ns_per_s)) {
        var now = datetime.Datetime.now().shiftTimezone(&datetime.timezones.Europe.Copenhagen);

        if (next.lte(now)) {
            channel.put(.{ .date = now });
            next = next.shiftMinutes(1);
        }
    }
}
