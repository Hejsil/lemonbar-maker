const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const mem = std.mem;

const Message = @import("../message.zig").Message;

pub fn mail(channel: *event.Channel(Message), home_dir: fs.Dir) void {
    const loop = event.Loop.instance.?;

    const mail_dir = home_dir.openDir(".local/share/mail", .{ .iterate = true }) catch return;
    // defer mail_dir.close();

    // TODO: Currently we just count the mails every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) : (loop.sleep(std.time.ns_per_min * 10)) {
        const res = count(mail_dir);
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

fn count(root: fs.Dir) Mail {
    var buf: [1024 * 1024]u8 = undefined;
    const fba = &heap.FixedBufferAllocator.init(&buf).allocator;
    var stack = std.ArrayList(fs.Dir).init(fba);
    defer for (stack.items) |*dir| dir.close();

    var res = Mail{ .unread = 0, .read = 0 };
    stack.append(root) catch return res;

    while (stack.popOrNull()) |*dir| {
        defer dir.close();

        var it = dir.iterate();
        while (it.next() catch null) |entry| {
            switch (entry.kind) {
                .Directory => {
                    const sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                    stack.append(sub_dir) catch continue;
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
