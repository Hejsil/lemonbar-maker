const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const log = std.log;
const mem = std.mem;

const State = @import("../main.zig").State;

pub fn mail(state: *State, home_dir: fs.Dir) void {
    // TODO: Currently we just count the mails every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) : (std.time.sleep(std.time.ns_per_s)) {
        var mail_dir = home_dir.openIterableDir(".local/share/mail", .{}) catch |err| {
            return log.err("Failed to open .local/share/mail: {}", .{err});
        };
        defer mail_dir.close();

        const res = count(mail_dir) catch |err| {
            log.warn("Failed to count mail: {}", .{err});
            continue;
        };

        state.mutex.lock();
        state.mail_unread = res.unread;
        state.mutex.unlock();
    }
}

const Mail = struct {
    unread: usize,
    read: usize,
};

fn count(root: fs.IterableDir) !Mail {
    var buf: [1024 * 1024]u8 = undefined;
    var fba_state = heap.FixedBufferAllocator.init(&buf);
    const fba = fba_state.allocator();
    var stack = std.ArrayList(fs.IterableDir).init(fba);

    var res = Mail{ .unread = 0, .read = 0 };
    try stack.append(root);

    // Never close root dir
    errdefer for (stack.items) |*dir|
        if (dir.dir.fd != root.dir.fd) dir.close();

    while (stack.popOrNull()) |_dir| {
        var dir = _dir;
        defer if (dir.dir.fd != root.dir.fd) dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .directory => if (!mem.eql(u8, entry.name, "Spam")) {
                    const sub_dir = try dir.dir.openIterableDir(entry.name, .{});
                    try stack.append(sub_dir);
                },
                else => {
                    res.unread += @intFromBool(mem.endsWith(u8, entry.name, ","));
                    res.read += @intFromBool(mem.endsWith(u8, entry.name, "S"));
                },
            }
        }
    }

    return res;
}
