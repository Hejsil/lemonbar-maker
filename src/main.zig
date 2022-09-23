const clap = @import("clap");
const datetime = @import("datetime");
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

    var state = State{ .now = Datetime.now() };

    log.debug("Setting up pipeline", .{});
    _ = try std.Thread.spawn(.{}, producer.date, .{&state});
    _ = try std.Thread.spawn(.{}, producer.date, .{&state});
    _ = try std.Thread.spawn(.{}, producer.mem, .{&state});
    _ = try std.Thread.spawn(.{}, producer.cpu, .{&state});
    _ = try std.Thread.spawn(.{}, producer.rss, .{ &state, home_dir });
    _ = try std.Thread.spawn(.{}, producer.mail, .{ &state, home_dir });
    _ = try std.Thread.spawn(.{}, producer.bspwm, .{&state});
    renderer(allocator, &state, .{
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
pub const State = struct {
    mutex: std.Thread.Mutex = .{},
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

// We seperate the renderer loop from the consumer loop, so that we can throttle
// how often we redraw the bar. If the consumer was to render the bar on every message,
// we would output multible bars when something happends close together. It is just
// better to wait for a few more messages before drawing. The renderer will look at
// the `locked_state` once in a while (N times per sec) and redraw of anything changed
// from the last iteration.
fn renderer(
    allocator: mem.Allocator,
    state: *State,
    options: Options,
) !void {
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

    while (true) : (std.time.sleep(std.time.ns_per_s / 15)) {
        const out = buf.writer();
        const curr = blk: {
            state.mutex.lock();
            defer state.mutex.unlock();
            break :blk state.*;
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
            try basicBlock(out, "mail{:>3}", .{curr.mail_unread});
            try out.writeAll(" ");
            try basicBlock(out, "rss{:>3}", .{curr.rss_unread});
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
    try writer.writeAll("mem");
    try writer.print("%{{F{s}}}{:>3}%%%{{F-}}", .{ color, memory_percent });
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
    try writer.writeAll("cpu");
    try writer.print("%{{F{s}}}{:>3}%%", .{ color, percent });
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
