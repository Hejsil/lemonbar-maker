const std = @import("std");

const event = std.event;
const fs = std.fs;
const log = std.log;
const os = std.os;

const State = @import("../main.zig").State;

pub fn rss(state: *State, home_dir: fs.Dir) !void {
    var read_buf: [1024]u8 = undefined;
    var unread_buf: [fs.MAX_PATH_BYTES]u8 = undefined;

    const unread_path = try home_dir.realpathZ(".local/share/rss/unread", &unread_buf);
    const watch = fs.File{
        .handle = try os.inotify_init1(0),
    };
    _ = try os.inotify_add_watch(
        watch.handle,
        unread_path,
        os.linux.IN.CREATE | os.linux.IN.DELETE | os.linux.IN.MOVE,
    );

    while (true) {
        var unread = home_dir.openDir(unread_path, .{ .iterate = true }) catch |err| {
            return log.err("Failed to open .local/share/rss/unread: {}", .{err});
        };
        defer unread.close();

        const unread_rss = count(unread) catch |err| {
            log.warn("Failed to read unread rss: {}", .{err});
            continue;
        };

        state.mutex.lock();
        state.rss_unread = unread_rss;
        state.mutex.unlock();

        _ = try watch.read(&read_buf);
    }
}

fn count(dir: fs.Dir) !usize {
    var res: usize = 0;
    var it = dir.iterate();
    while (try it.next()) |_|
        res += 1;

    return res;
}
