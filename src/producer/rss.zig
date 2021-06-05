const std = @import("std");

const event = std.event;
const fs = std.fs;
const log = std.log;

const Message = @import("../message.zig").Message;

pub fn rss(channel: *event.Channel(Message), home_dir: fs.Dir) void {
    const loop = event.Loop.instance.?;

    // TODO: Currently we just count the unread rss feeds every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) : (loop.sleep(std.time.ns_per_s * 10)) {
        var unread = home_dir.openDir(".local/share/rss/unread", .{ .iterate = true }) catch |err| {
            return log.err("Failed to open .local/share/rss/unread: {}", .{err});
        };
        defer unread.close();

        var read = home_dir.openDir(".local/share/rss/read", .{ .iterate = true }) catch |err| {
            return log.err("Failed to open .local/share/rss/unread: {}", .{err});
        };
        defer read.close();

        const unread_rss = count(unread) catch |err| {
            log.warn("Failed to read unread rss: {}", .{err});
            continue;
        };
        const read_rss = count(read) catch |err| {
            log.warn("Failed to read read rss: {}", .{err});
            continue;
        };
        channel.put(.{
            .rss = .{
                .unread = unread_rss,
                .read = read_rss,
            },
        });
    }
}

pub const Rss = struct {
    unread: usize,
    read: usize,
};

fn count(dir: fs.Dir) !usize {
    var res: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |_|
        res += 1;

    return res;
}
