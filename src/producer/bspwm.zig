const std = @import("std");

const ascii = std.ascii;
const event = std.event;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const os = std.os;
const process = std.process;

const Message = @import("../message.zig").Message;

pub fn bspwm(channel: *event.Channel(Message)) void {
    const loop = event.Loop.instance.?;

    // TODO: Don't hardcode path to bspwm socket
    const sock_addr = os.sockaddr_un{ .path = ("/tmp/bspwm_0_0-socket" ++ "\x00" ** 87).* };
    const socket = os.socket(os.AF_UNIX, os.SOCK_STREAM, 0) catch return;
    defer os.close(socket);

    loop.connect(socket, @ptrCast(*const os.sockaddr, &sock_addr), @sizeOf(os.sockaddr_un)) catch return;
    _ = loop.sendto(socket, "subscribe\x00report\x00", 0, null, 0) catch return;

    var buf: [1024]u8 = undefined;
    while (true) {
        const len = loop.recvfrom(socket, &buf, 0, null, null) catch continue;
        const line = buf[1 .. len - 1]; // Remove leading 'W' and trailing '\n'

        var curr_monitor: usize = 0;
        var next_monitor: usize = 0;
        var curr_workspace: usize = 0;

        var it = mem.tokenize(line, ":");
        while (it.next()) |item| {
            var name: [7:0]u8 = [1:0]u8{0} ** 7;
            mem.copy(u8, &name, item[0..math.min(item.len, 7)]);

            switch (item[0]) {
                'm', 'M' => {
                    curr_workspace = 0;
                    curr_monitor = next_monitor;
                    next_monitor += 1;
                },
                'O', 'o', 'F', 'f', 'U', 'u' => {
                    channel.put(.{
                        .workspace = .{
                            .id = curr_workspace,
                            .monitor_id = curr_monitor,
                            .flags = .{
                                .focused = ascii.isUpper(item[0]),
                                .occupied = ascii.toUpper(item[0]) != 'F',
                            },
                        },
                    });
                    curr_workspace += 1;
                },
                else => continue,
            }
        }
    }
}
