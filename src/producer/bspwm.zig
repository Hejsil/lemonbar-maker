const std = @import("std");

const ascii = std.ascii;
const event = std.event;
const fs = std.fs;
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;
const process = std.process;

const State = @import("../main.zig").State;

pub fn bspwm(state: *State) void {
    // TODO: Don't hardcode path to bspwm socket
    const sock_addr = os.sockaddr.un{ .path = ("/tmp/bspwm_0_0-socket" ++ "\x00" ** 87).* };
    const socket = os.socket(os.AF.UNIX, os.SOCK.STREAM, 0) catch |err| {
        return log.err("Failed to get bspwm socket: {}", .{err});
    };
    defer os.close(socket);

    os.connect(socket, @ptrCast(&sock_addr), @sizeOf(os.sockaddr.un)) catch |err| {
        return log.err("Failed to connect to bspwm socket: {}", .{err});
    };
    _ = os.sendto(socket, "subscribe\x00report\x00", 0, null, 0) catch |err| {
        return log.err("Failed to subscribe to bspwm reports: {}", .{err});
    };

    var buf: [1024]u8 = undefined;
    while (true) {
        const len = os.recvfrom(socket, &buf, 0, null, null) catch |err| {
            log.warn("Failed to read data from bspwm socket: {}", .{err});
            continue;
        };
        const lines = buf[0..len];

        // Skip to the last line an only process that
        var it = mem.tokenize(u8, lines, "\n");
        var last = it.next().?;
        while (it.next()) |next| : (last = next) {}

        const line = last[1..]; // Remove leading 'W'
        log.debug("bspwm report: {s}", .{line});
        processLine(line, state);
    }
}

fn processLine(line: []const u8, state: *State) void {
    state.mutex.lock();
    defer state.mutex.unlock();

    var curr_monitor: usize = 0;
    var next_monitor: usize = 0;
    var curr_workspace: usize = 0;

    var it = mem.tokenize(u8, line, ":");
    while (it.next()) |item| {
        switch (item[0]) {
            'm', 'M' => {
                curr_workspace = 0;
                curr_monitor = next_monitor;
                next_monitor += 1;
            },
            'O', 'o', 'F', 'f', 'U', 'u' => {
                const mon = &state.monitors[curr_monitor];
                mon.is_active = true;
                mon.workspaces[curr_workspace] = .{
                    .is_active = true,
                    .focused = ascii.isUpper(item[0]),
                    .occupied = ascii.toUpper(item[0]) != 'F',
                };

                curr_workspace += 1;
            },
            else => {},
        }
    }
}
