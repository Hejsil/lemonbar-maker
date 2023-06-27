const mecha = @import("mecha");
const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const log = std.log;

const State = @import("../main.zig").State;

pub fn memory(state: *State) void {
    const cwd = fs.cwd();

    // On my system, `cat /proc/meminfo | wc -c` gives 1419, so this buffer
    // should be enough to hold all data read from meminfo.
    var buf: [1024 * 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init("");

    while (true) : (std.time.sleep(std.time.ns_per_s)) {
        const content = cwd.readFile("/proc/meminfo", &buf) catch |err| {
            log.warn("Failed to read /proc/meminfo: {}", .{err});
            continue;
        };
        const result = parser.parse(fba.allocator(), content) catch |err| {
            log.warn("Error while parsing /proc/meminfo: {}", .{err});
            continue;
        };

        const used = result.value.mem_total - result.value.mem_available;
        state.mutex.lock();
        state.mem_percent_used = @intCast((used * 100) / result.value.mem_total);
        state.mutex.unlock();
    }
}

const Mem = struct {
    mem_total: usize,
    mem_free: usize,
    mem_available: usize,
};

const parser = blk: {
    @setEvalBranchQuota(1000000000);
    break :blk mecha.combine(.{
        field("MemTotal"),
        field("MemFree"),
        field("MemAvailable"),
    }).map(mecha.toStruct(Mem));
};

fn field(comptime name: []const u8) mecha.Parser(usize) {
    return mecha.combine(.{
        mecha.string(name ++ ":").discard(),
        mecha.ascii.char(' ').many(.{ .collect = false }).discard(),
        mecha.int(usize, .{}),
        mecha.string(" kB").opt().discard(),
        mecha.ascii.char('\n').discard(),
    });
}
