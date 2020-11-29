const std = @import("std");

const event = std.event;
const fs = std.fs;

const Message = @import("../message.zig").Message;

pub fn rss(channel: *event.Channel(Message), home_dir: fs.Dir) void {
    const loop = event.Loop.instance.?;

    const unread = home_dir.openDir(".cache/rss/unread", .{ .iterate = true }) catch return;
    // defer unread.close();

    const read = home_dir.openDir(".cache/rss/read", .{ .iterate = true }) catch return;
    // defer read.close();

    // TODO: Currently we just count the unread rss feeds every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) {
        channel.put(.{
            .rss = .{
                .unread = count(unread),
                .read = count(read),
            },
        });

        loop.sleep(std.time.ns_per_min * 10);
    }
}

pub const Rss = struct {
    unread: usize,
    read: usize,
};

fn count(dir: fs.Dir) usize {
    var res: usize = 0;
    var it = dir.iterate();
    while (it.next() catch null) |_|
        res += 1;

    return res;
}
