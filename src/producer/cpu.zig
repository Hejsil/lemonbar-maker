const std = @import("std");
const mecha = @import("mecha");

const event = std.event;
const fs = std.fs;

const Message = @import("../message.zig").Message;

pub fn cpu(channel: *event.Channel(Message)) void {
    const loop = event.Loop.instance.?;
    const cwd = fs.cwd();

    // On my system, `cat /proc/meminfo | wc -c` gives 3574. This is with a system
    // that has 16 threads. We ensure that our buffer is quite a lot bigger so that
    // we have room for systems with a lot more threads. This buffer size is just a
    // guess though.
    var buf: [1024 * 1024]u8 = undefined;

    while (true) {
        var content: []const u8 = cwd.readFile("/proc/stat", &buf) catch continue;
        if (first_line(content)) |res|
            content = res.rest;

        while (line(content)) |result| : (content = result.rest)
            channel.put(.{ .cpu = result.value });

        loop.sleep(std.time.ns_per_s);
    }
}

pub const Cpu = struct {
    number: usize,
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
    mecha.manyN(10, mecha.combine(.{
        mecha.discard(mecha.many(mecha.char(' '))),
        mecha.int(usize, 10),
    })),
    mecha.char('\n'),
});

const line = mecha.as(Cpu, mecha.toStruct(Cpu), mecha.combine(.{
    mecha.string("cpu"),
    mecha.int(usize, 10),
    mecha.as(CpuInfo, mecha.toStruct(CpuInfo), mecha.manyN(10, mecha.combine(.{
        mecha.discard(mecha.many(mecha.char(' '))),
        mecha.int(usize, 10),
    }))),
    mecha.char('\n'),
}));
