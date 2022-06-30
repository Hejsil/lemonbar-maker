const clap = @import("clap");
const datetime = @import("datetime");
const message = @import("message.zig");
const producer = @import("producer.zig");
const sab = @import("sab");
const std = @import("std");

const event = std.event;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const log = std.log;
const math = std.math;
const mem = std.mem;
const process = std.process;

const Datetime = datetime.Datetime;

pub const io_mode = io.Mode.evented;

const parsers = .{ .COLOR = clap.parsers.string };

const params = clap.parseParamsComptime(
    \\-h, --help          Print this message to stdout
    \\-l, --low <COLOR>   The color when a bar is a low value
    \\-m, --mid <COLOR>   The color when a bar is a medium value
    \\-h, --high <COLOR>  The color when a bar is a high value
    \\
);

fn usage(stream: anytype) !void {
    try stream.writeAll("Usage: ");
    try clap.usage(stream, clap.Help, &params);
    try stream.writeAll(
        \\
        \\Help message here
        \\
        \\Options:
        \\
    );
    try clap.help(stream, clap.Help, &params, .{});
}

pub fn main() !void {
    var gba = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gba.allocator();
    defer _ = gba.deinit();

    log.debug("Parsing arguments", .{});
    var diag = clap.Diagnostic{};
    var clap_res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag }) catch |err| {
        const stderr = io.getStdErr().writer();
        diag.report(stderr, err) catch {};
        usage(stderr) catch {};
        return err;
    };
    defer clap_res.deinit();

    const args = clap_res.args;
    if (args.help)
        return try usage(io.getStdOut().writer());

    const low = args.low orelse "-";
    const mid = args.mid orelse "-";
    const high = args.high orelse "-";

    log.debug("Getting $HOME", .{});
    const home_dir_path = try process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir_path);

    var home_dir = try fs.cwd().openDir(home_dir_path, .{});
    defer home_dir.close();

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
        .lock = .{},
        .private_data = .{ .now = Datetime.now() },
    };

    log.debug("Setting up pipeline", .{});
    _ = async producer.date(&channel);
    _ = async producer.mem(&channel);
    _ = async producer.cpu(&channel);
    _ = async producer.rss(&channel, home_dir);
    _ = async producer.mail(&channel, home_dir);
    _ = async producer.bspwm(&channel);
    _ = async consumer(&channel, &locked_state);
    renderer(allocator, &locked_state, .{
        .low = low,
        .mid = mid,
        .high = high,
    }) catch |err| {
        log.err("Failed to render bar: {}", .{err});
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
    now: Datetime,
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
fn renderer(
    allocator: mem.Allocator,
    locked_state: *event.Locked(State),
    options: Options,
) !void {
    const loop = event.Loop.instance.?;
    const stdout = io.getStdOut().writer();
    var buf = std.ArrayList(u8).init(allocator);
    var prev_buf = std.ArrayList(u8).init(allocator);

    const bars = [_][]const u8{
        try fmt.allocPrint(allocator, "%{{F{s}}} ", .{options.low}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▁", .{options.low}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▂", .{options.low}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▃", .{options.mid}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▄", .{options.mid}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▅", .{options.mid}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▆", .{options.high}),
        try fmt.allocPrint(allocator, "%{{F{s}}}▇", .{options.high}),
        try fmt.allocPrint(allocator, "%{{F{s}}}█", .{options.high}),
    };

    while (true) : (loop.sleep(std.time.ns_per_s / 15)) {
        const out = buf.writer();
        const curr = blk: {
            const held = locked_state.acquire();
            defer held.release();
            break :blk held.value.*;
        };

        for (curr.monitors) |monitor, mon_id| {
            if (!monitor.is_active)
                continue;
            try out.print("%{{S{}}}", .{mon_id});

            try left(out);
            try out.writeAll(" ");
            try workspaceBlock(out, &monitor.workspaces);

            try center(out);
            try memoryBlock(out, options, curr.mem_percent_used);
            try out.writeAll(" ");
            try cpuBlock(out, options, &bars, &curr.cpu_percent);

            try right(out);
            try basicBlock(out, "mail {:>2}", .{curr.mail_unread});
            try out.writeAll(" ");
            try basicBlock(out, "rss {:>2}", .{curr.rss_unread});
            try out.writeAll(" ");
            try dateBlock(out, curr.now);
            try out.writeAll(" ");
        }
        try out.writeAll("\n");

        if (!mem.eql(u8, buf.items, prev_buf.items)) {
            // If nothing changed from prev iteration, then there is no reason to output it.
            try stdout.writeAll(buf.items);
            mem.swap(std.ArrayList(u8), &buf, &prev_buf);
        }

        buf.shrinkRetainingCapacity(0);
    }
}

fn workspaceBlock(writer: anytype, workspaces: []const Workspace) !void {
    try writer.writeAll("%{+o}");
    for (workspaces) |workspace, i| {
        if (!workspace.is_active)
            continue;

        const focus: usize = @boolToInt(workspace.focused);
        const occupied: usize = @boolToInt(workspace.occupied);
        try writer.print("{s} {}{s}{s}", .{
            ([_][]const u8{ "", "%{+u}" })[focus],
            i + 1,
            ([_][]const u8{ " ", "*" })[occupied],
            ([_][]const u8{ "", "%{-u}" })[focus],
        });
    }
    try writer.writeAll("%{-o}");
}

fn memoryBlock(writer: anytype, options: Options, memory_percent: usize) !void {
    const color = percentToColor(memory_percent, options);

    try blockBegin(writer);
    try writer.writeAll("mem ");
    try writer.print("%{{F{s}}}{:>2}%%%{{F-}}", .{ color, memory_percent });
    try blockEnd(writer);
}

fn cpuBlock(
    writer: anytype,
    options: Options,
    bars: []const []const u8,
    cpu_percent: []const ?u8,
) !void {
    try blockBegin(writer);
    var total: usize = 0;
    var count: usize = 0;
    for (cpu_percent) |m_cpu| {
        const cpu = m_cpu orelse continue;
        total += cpu;
        count += 1;
        try sab.draw(writer, u8, cpu, .{ .len = 1, .steps = bars });
    }
    try writer.writeAll("%{F-}");
    try blockEnd(writer);

    const percent = if (count == 0) 0 else total / count;
    const color = percentToColor(percent, options);
    try writer.writeAll(" ");
    try blockBegin(writer);
    try writer.writeAll("cpu ");
    try writer.print("%{{F{s}}}{:>2}%%", .{ color, percent });
    try writer.writeAll("%{F-}");
    try blockEnd(writer);
}

fn dateBlock(writer: anytype, now: Datetime) !void {

    // Danish daylight saving fixup code
    var date = now;
    const summer_start = try Datetime.create(date.date.year, 3, 28, 2, 0, 0, 0, date.zone);
    const summer_end = try Datetime.create(date.date.year, 10, 31, 3, 0, 0, 0, date.zone);
    if (summer_start.lte(date) and date.lte(summer_end))
        date = date.shiftHours(1);

    try blockBegin(writer);
    try writer.print("Week {} {s} {d:0>2} {s} {d:0>2}:{d:0>2}", .{
        date.date.weekOfYear(),
        date.date.monthName()[0..3],
        date.date.day,
        @tagName(date.date.dayOfWeek())[0..3],
        date.time.hour,
        date.time.minute,
    });
    try blockEnd(writer);
}

fn basicBlock(writer: anytype, comptime format: []const u8, args: anytype) !void {
    try blockBegin(writer);
    try writer.print(format, args);
    try blockEnd(writer);
}

fn left(writer: anytype) !void {
    try writer.writeAll("%{l}");
}

fn center(writer: anytype) !void {
    try writer.writeAll("%{c}");
}

fn right(writer: anytype) !void {
    try writer.writeAll("%{r}");
}

fn blockBegin(writer: anytype) !void {
    try writer.writeAll("%{+o} ");
}

fn blockEnd(writer: anytype) !void {
    try writer.writeAll(" %{-o}");
}

fn percentToColor(percent: usize, options: Options) []const u8 {
    return switch (percent / 33) {
        0 => options.low,
        1 => options.mid,
        else => options.high,
    };
}
