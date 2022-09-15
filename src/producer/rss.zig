const std = @import("std");

const event = std.event;
const fs = std.fs;
const log = std.log;

const State = @import("../main.zig").State;

pub fn rss(state: *State, home_dir: fs.Dir) void {
    // TODO: Currently we just count the unread rss feeds every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) : (std.time.sleep(std.time.ns_per_s * 10)) {
        var unread = home_dir.openIterableDir(".local/share/rss/unread", .{}) catch |err| {
            return log.err("Failed to open .local/share/rss/unread: {}", .{err});
        };
        defer unread.close();

        // var read = home_dir.openIterableDir(".local/share/rss/read", .{}) catch |err| {
        //     return log.err("Failed to open .local/share/rss/unread: {}", .{err});
        // };
        // defer read.close();

        const unread_rss = count(unread) catch |err| {
            log.warn("Failed to read unread rss: {}", .{err});
            continue;
        };
        // const read_rss = count(read) catch |err| {
        //     log.warn("Failed to read read rss: {}", .{err});
        //     continue;
        // };

        state.mutex.lock();
        state.rss_unread = unread_rss;
        state.mutex.unlock();
    }
}

fn count(dir: fs.IterableDir) !usize {
    var res: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |_|
        res += 1;

    return res;
}
