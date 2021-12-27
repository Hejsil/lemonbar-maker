const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const log = std.log;
const mem = std.mem;

const Message = @import("../message.zig").Message;

pub fn mail(channel: *event.Channel(Message), home_dir: fs.Dir) void {
    const loop = event.Loop.instance.?;

    // TODO: Currently we just count the mails every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) : (loop.sleep(std.time.ns_per_s * 10)) {
        var mail_dir = home_dir.openDir(".local/share/mail", .{ .iterate = true }) catch |err| {
            return log.err("Failed to open .local/share/mail: {}", .{err});
        };
        defer mail_dir.close();

        const res = count(mail_dir) catch |err| {
            log.warn("Failed to count mail: {}", .{err});
            continue;
        };

        channel.put(.{
            .mail = .{
                .read = res.read,
                .unread = res.unread,
            },
        });
    }
}

pub const Mail = struct {
    unread: usize,
    read: usize,
};

fn count(root: fs.Dir) !Mail {
    var buf: [1024 * 1024]u8 = undefined;
    const fba = heap.FixedBufferAllocator.init(&buf).allocator();
    var stack = std.ArrayList(fs.Dir).init(fba);

    var res = Mail{ .unread = 0, .read = 0 };
    try stack.append(root);

    // Never close root dir
    errdefer for (stack.items) |*dir|
        if (dir.fd != root.fd) dir.close();

    while (stack.popOrNull()) |*dir| {
        defer if (dir.fd != root.fd) dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .Directory => {
                    const sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                    try stack.append(sub_dir);
                },
                else => {
                    res.unread += @boolToInt(mem.endsWith(u8, entry.name, ","));
                    res.read += @boolToInt(mem.endsWith(u8, entry.name, "S"));
                },
            }
        }
    }

    return res;
}
