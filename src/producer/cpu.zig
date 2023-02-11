const mecha = @import("mecha");
const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const log = std.log;
const math = std.math;

const State = @import("../main.zig").State;

pub fn cpu(state: *State) void {
    const cwd = fs.cwd();

    // On my system, `cat /proc/meminfo | wc -c` gives 3574. This is with a system
    // that has 16 threads. We ensure that our buffer is quite a lot bigger so that
    // we have room for systems with a lot more threads. This buffer size is just a
    // guess though.
    var buf: [1024 * 1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init("");

    var cpu_last = [_]CpuLast{.{}} ** 128;

    while (true) {
        var content: []const u8 = cwd.readFile("/proc/stat", &buf) catch |err| {
            log.warn("Failed to read /proc/stat: {}", .{err});
            continue;
        };
        if (first_line(fba.allocator(), content)) |res| {
            content = res.rest;
        } else |_| {}

        state.mutex.lock();
        while (line(fba.allocator(), content)) |result| : (content = result.rest) {
            const info = result.value.info;
            const i = result.value.id;
            const last = cpu_last[i];
            const user = math.sub(usize, info.user, last.user) catch 0;
            const sys = math.sub(usize, info.sys, last.sys) catch 0;
            const idle = math.sub(usize, info.idle, last.idle) catch 0;
            const cpu_usage = ((user + sys) * 100) / math.max(1, user + sys + idle);
            state.cpu_percent[i] = @intCast(u8, cpu_usage);
            cpu_last[i] = .{
                .user = info.user,
                .sys = info.sys,
                .idle = info.idle,
            };
        } else |_| {}
        state.mutex.unlock();

        std.time.sleep(std.time.ns_per_s);
    }
}

const CpuLast = struct {
    user: usize = 0,
    sys: usize = 0,
    idle: usize = 0,
};

const Cpu = struct {
    id: usize,
    info: CpuInfo,
};

const CpuInfo = struct {
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
    mecha.discard(mecha.ascii.char('\n')),
});

const line = mecha.map(Cpu, mecha.toStruct(Cpu), mecha.combine(.{
    mecha.string("cpu"),
    mecha.int(usize, .{}),
    mecha.map(CpuInfo, mecha.toStruct(CpuInfo), mecha.manyN(mecha.combine(.{
        mecha.discard(mecha.many(mecha.ascii.char(' '), .{ .collect = false })),
        mecha.int(usize, .{}),
    }), 10, .{})),
    mecha.discard(mecha.ascii.char('\n')),
}));
