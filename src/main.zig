const clap = @import("clap");
const datetime = @import("datetime");
const message = @import("message.zig");
const producer = @import("producer.zig");
const sab = @import("sab");
const std = @import("std");

const event = std.event;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const process = std.process;

pub const io_mode = io.Mode.evented;

const params = comptime blk: {
    @setEvalBranchQuota(100000);
    break :blk [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help           Print this message to stdout") catch unreachable,
        clap.parseParam("-l, --low <COLOR>    The color when a bar is a low value.") catch unreachable,
        clap.parseParam("-m, --mid <COLOR>    The color when a bar is a medium value.") catch unreachable,
        clap.parseParam("-h, --high <COLOR>   The color when a bar is a high value.") catch unreachable,
    };
};

fn usage(stream: anytype) !void {
    try stream.writeAll("Usage: ");
    try clap.usage(stream, &params);
    try stream.writeAll(
        \\
        \\Help message here
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

pub fn main() !void {
    var gba = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gba.allocator;
    defer _ = gba.deinit();

    log.debug("Parsing arguments", .{});
    var diag = clap.Diagnostic{};
    var args = clap.parse(clap.Help, &params, allocator, &diag) catch |err| {
        const stderr = io.getStdErr().writer();
        diag.report(stderr, err) catch {};
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(io.getStdOut().writer());

    const low = args.option("--low") orelse "-";
    const mid = args.option("--mid") orelse "-";
    const high = args.option("--high") orelse "-";

    log.debug("Getting $HOME", .{});
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
    var buf: [128]message.Message = undefined;
    var channel: event.Channel(message.Message) = undefined;
    channel.init(&buf);

    // event.Locked.init doesn't compile...
    var locked_state = event.Locked(State){
        .lock = event.Lock{},
        .private_data = State{ .now = datetime.Datetime.now() },
    };

    log.debug("Setting up pipeline", .{});
    const f1 = async producer.date(&channel);
    const f2 = async producer.mem(&channel);
    const f3 = async producer.cpu(&channel);
    const f4 = async producer.rss(&channel, allocator, home_dir);
    const f5 = async producer.mail(&channel, home_dir);
    const f6 = async producer.bspwm(&channel);
    const f7 = async consumer(&channel, &locked_state);
    renderer(&locked_state, .{
        .low = low,
        .mid = mid,
        .high = high,
    }) catch |err| {
        log.emerg("Failed to render bar: {}", .{err});
        return err;
    };

    log.debug("Goodnight", .{});
}

const Options = struct {
    low: []const u8,
    mid: []const u8,
    high: []const u8,
};

// This structure should be deep copiable, so that the renderer can keep
// track of a `prev` version of the state for comparison.
const State = struct {
    now: datetime.Datetime,
    mem_percent_used: u8 = 0,
    rss_unread: usize = 0,
    mail_unread: usize = 0,

    // Support up to 128 threads
    cpu_percent: [128]?u8 = [_]?u8{null} ** 128,
    monitors: [4]Monitor = [_]Monitor{.{}} ** 4,
};

const Monitor = struct {
    is_active: bool = false,
    workspaces: [20]Workspace = [_]Workspace{.{}} ** 20,
};

const Workspace = packed struct {
    is_active: bool = false,
    focused: bool = false,
    occupied: bool = false,
};

fn consumer(channel: *event.Channel(message.Message), locked_state: *event.Locked(State)) void {
    const Cpu = struct {
        user: usize = 0,
        sys: usize = 0,
        idle: usize = 0,
    };

    var cpu_last = [_]Cpu{.{}} ** 128;
    while (true) {
        const change = channel.get();
        const held = locked_state.acquire();
        const state = held.value;
        defer held.release();

        switch (change) {
            .date => |now| state.now = now,
            .rss => |rss| state.rss_unread = rss.unread,
            .mail => |mail| state.mail_unread = mail.unread,
            .mem => |memory| {
                const used = memory.total - memory.available;
                state.mem_percent_used = @intCast(u8, (used * 100) / memory.total);
            },
            .cpu => |cpu| {
                const i = cpu.id;
                const last = cpu_last[i];
                const user = math.sub(usize, cpu.user, last.user) catch 0;
                const sys = math.sub(usize, cpu.sys, last.sys) catch 0;
                const idle = math.sub(usize, cpu.idle, last.idle) catch 0;
                const cpu_usage = ((user + sys) * 100) / math.max(1, user + sys + idle);
                state.cpu_percent[i] = @intCast(u8, cpu_usage);
                cpu_last[i] = .{
                    .user = cpu.user,
                    .sys = cpu.sys,
                    .idle = cpu.idle,
                };
            },
            .workspace => |workspace| {
                const mon = &state.monitors[workspace.monitor_id];
                mon.is_active = true;
                mon.workspaces[workspace.id] = .{
                    .is_active = true,
                    .focused = workspace.flags.focused,
                    .occupied = workspace.flags.occupied,
                };
            },
        }
    }
}

// We seperate the renderer loop from the consumer loop, so that we can throttle
// how often we redraw the bar. If the consumer was to render the bar on every message,
// we would output multible bars when something happends close together. It is just
// better to wait for a few more messages before drawing. The renderer will look at
// the `locked_state` once in a while (N times per sec) and redraw of anything changed
// from the last iteration.
fn renderer(locked_state: *event.Locked(State), options: Options) !void {
    var buf: [1024]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(&buf);
    const loop = event.Loop.instance.?;
    const out = io.bufferedWriter(io.getStdOut().writer()).writer();

    const bars = [_][]const u8{
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▁", .{options.low}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▂", .{options.low}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▃", .{options.low}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▄", .{options.mid}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▅", .{options.mid}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▆", .{options.high}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}▇", .{options.high}),
        try std.fmt.allocPrint(&fba.allocator, "%{{F{}}}█", .{options.high}),
    };

    var prev = blk: {
        const held = locked_state.acquire();
        defer held.release();
        break :blk held.value.*;
    };
    while (true) : (loop.sleep(std.time.ns_per_s / 15)) {
        const curr = blk: {
            const held = locked_state.acquire();
            defer held.release();
            break :blk held.value.*;
        };

        if (std.meta.eql(prev, curr))
            continue;

        prev = curr;
        for (curr.monitors) |monitor, mon_id| {
            if (!monitor.is_active)
                continue;
            try out.print("%{{S{}}}", .{mon_id});

            try out.writeAll("%{l} ");
            for (monitor.workspaces) |workspace, i| {
                if (!workspace.is_active)
                    continue;

                const focus: usize = @boolToInt(workspace.focused);
                const occupied: usize = @boolToInt(workspace.occupied);
                try out.print("%{{+o}}{} {}{}{}%{{-o}}", .{
                    ([_][]const u8{ "", "%{+u}" })[focus],
                    i + 1,
                    ([_][]const u8{ " ", "*" })[occupied],
                    ([_][]const u8{ "", "%{-u}" })[focus],
                });
            }

            try out.writeAll("%{r}");
            try out.print("%{{+o}} mail:{:>3} %{{-o}} ", .{curr.mail_unread});
            try out.print("%{{+o}} rss:{:>3} %{{-o}} ", .{curr.rss_unread});

            try out.writeAll("%{+o} mem: ");
            try sab.draw(out, u8, curr.mem_percent_used, .{ .len = 1, .steps = &bars });
            try out.writeAll("%{F-} %{-o} ");

            try out.writeAll("%{+o} cpu: ");
            for (curr.cpu_percent) |m_cpu| {
                const cpu = m_cpu orelse continue;
                try sab.draw(out, u8, cpu, .{ .len = 1, .steps = &bars });
            }
            try out.writeAll("%{F-} %{-o} ");

            try out.print("%{{+o}} {} {d:0>2} {} {d:0>2}:{d:0>2} %{{-o}} ", .{
                curr.now.date.monthName()[0..3],
                curr.now.date.day,
                @tagName(curr.now.date.dayOfWeek())[0..3],
                curr.now.time.hour,
                curr.now.time.minute,
            });
        }
        try out.writeAll("\n");
        try out.context.flush();
    }
}
