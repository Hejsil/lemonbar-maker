const producer = @import("producer.zig");
const std = @import("std");

const event = std.event;
const fs = std.fs;
const io = std.io;
const process = std.process;

const Message = @import("message.zig").Message;

pub const io_mode = io.Mode.evented;

pub fn main() !void {
    var gba = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gba.deinit();
    const allocator = &gba.allocator;

    const home_dir_path = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir_path);

    const home_dir = try fs.cwd().openDir(home_dir_path, .{});
    //defer home_dir.close();

    // Seems like ChildProcess is broken with `io_mode == .evented`
    // broken LLVM module found: Basic Block in function 'std.child_process.ChildProcess.spawnPosix'
    // does not have terminator!
    // label %OkResume
    //const xtitle = try std.ChildProcess.init(&[_][]const u8{"xtitle"}, allocator);
    //try xtitle.spawn();
    var buf: [1024]Message = undefined;
    var channel: event.Channel(Message) = undefined;
    channel.init(&buf);

    const f1 = async producer.date(&channel);
    const f2 = async producer.mem(&channel);
    const f3 = async producer.cpu(&channel);
    const f4 = async producer.rss(&channel, home_dir);
    const f5 = async producer.mail(&channel, home_dir);
    const f6 = async producer.bspwm(&channel);
    consumer(&channel);
}

fn consumer(channel: *event.Channel(Message)) void {
    const out = io.bufferedOutStream(io.getStdOut().writer()).writer();
    while (true) {
        const change = channel.get();
        defer out.context.flush() catch {};

        (switch (change) {
            .date => |now| out.print("{} {d:0>2} {} {d:0>2}:{d:0>2}\n", .{
                now.date.monthName()[0..3],
                now.date.day,
                @tagName(now.date.dayOfWeek())[0..3],
                now.time.hour,
                now.time.minute,
            }),
            .mem => |mem| out.print("{}\n", .{
                mem,
                //@floatToInt(usize, (@intToFloat(f32, mem.total - mem.available) / @intToFloat(f32, mem.total)) * 100),
            }),
            .cpu => |cpu| out.print("{}\n", .{
                cpu,
            }),
            .rss => |rss| out.print("{}\n", .{
                rss,
            }),
            .mail => |mail| out.print("{}\n", .{
                mail,
            }),
            .bspwm => |bspwm| out.print("{}\n", .{
                bspwm,
            }),
        }) catch {};
    }
}
