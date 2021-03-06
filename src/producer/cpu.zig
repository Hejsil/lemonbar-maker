const mecha = @import("mecha");
const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const log = std.log;

const Message = @import("../message.zig").Message;

pub fn cpu(channel: *event.Channel(Message)) void {
    const loop = event.Loop.instance.?;
    const cwd = fs.cwd();

    // On my system, `cat /proc/meminfo | wc -c` gives 3574. This is with a system
    // that has 16 threads. We ensure that our buffer is quite a lot bigger so that
    // we have room for systems with a lot more threads. This buffer size is just a
    // guess though.
    var buf: [1024 * 1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init("");

    while (true) {
        var content: []const u8 = cwd.readFile("/proc/stat", &buf) catch |err| {
            log.warn("Failed to read /proc/stat: {}", .{err});
            continue;
        };
        if (first_line(&fba.allocator, content)) |res| {
            content = res.rest;
        } else |_| {}

        while (line(&fba.allocator, content)) |result| : (content = result.rest) {
            channel.put(.{
                .cpu = .{
                    .id = result.value.id,
                    .user = result.value.cpu.user,
                    .sys = result.value.cpu.sys,
                    .idle = result.value.cpu.idle,
                },
            });
        } else |_| {}

        loop.sleep(std.time.ns_per_s);
    }
}

pub const Cpu = struct {
    id: usize,
    cpu: CpuInfo,
};

pub const CpuInfo = struct {
    user: usize,
    nice: usize,
    sys: usize,
    idle: usize,
    iowait: usize,
    hardirq: usize,
    softirq: usize,
    steal: usize,
    guest: usize,
    guest_nice: usize,
};

const first_line = mecha.combine(.{
    mecha.string("cpu"),
    mecha.manyN(mecha.combine(.{
        mecha.discard(mecha.many(mecha.ascii.char(' '), .{ .collect = false })),
        mecha.int(usize, .{}),
    }), 10, .{}),
    mecha.ascii.char('\n'),
});

const line = mecha.map(Cpu, mecha.toStruct(Cpu), mecha.combine(.{
    mecha.string("cpu"),
    mecha.int(usize, .{}),
    mecha.map(CpuInfo, mecha.toStruct(CpuInfo), mecha.manyN(mecha.combine(.{
        mecha.discard(mecha.many(mecha.ascii.char(' '), .{ .collect = false })),
        mecha.int(usize, .{}),
    }), 10, .{})),
    mecha.ascii.char('\n'),
}));
