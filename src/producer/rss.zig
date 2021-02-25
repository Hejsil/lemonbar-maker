const mecha = @import("mecha");
const std = @import("std");

const event = std.event;
const fs = std.fs;
const log = std.log;
const mem = std.mem;

const Message = @import("../message.zig").Message;

pub fn rss(channel: *event.Channel(Message), allocator: *mem.Allocator, home_dir: fs.Dir) !void {
    const loop = event.Loop.instance.?;
    const feed_dir_path = try std.process.getEnvVarOwned(allocator, "sfeedpath");
    const read_file_path = try std.process.getEnvVarOwned(allocator, "SFEED_URL_FILE");

    var feed_file_buf = std.ArrayList(u8).init(allocator);
    var read_file_buf = std.ArrayList(u8).init(allocator);
    var feeds_read = std.StringHashMap(void).init(allocator);

    try feed_file_buf.resize(mem.page_size);
    try read_file_buf.resize(mem.page_size);

    // TODO: Currently we just count the unread rss feeds every so often. In an ideal world,
    //       we wait for file system events, but it seems that Zigs `fs.Watch` haven't been
    //       worked on for a while, so I'm not gonna try using it.
    while (true) : (loop.sleep(std.time.ns_per_s * 10)) {
        {
            feeds_read.clearRetainingCapacity();
            const read_file_data = try readIntoArrayList(home_dir, read_file_path, &read_file_buf);
            var line_it = mem.split(read_file_data, "\n");
            while (line_it.next()) |line|
                try feeds_read.put(line, {});
        }

        var unread: usize = 0;
        var feed_dir = try home_dir.openDir(feed_dir_path, .{ .iterate = true });
        defer feed_dir.close();

        var feed_it = feed_dir.iterate();
        while (try feed_it.next()) |entry| {
            var rest: []const u8 = try readIntoArrayList(feed_dir, entry.name, &feed_file_buf);
            while (feedParser(undefined, rest)) |res| : (rest = res.rest) {
                unread += @boolToInt(feeds_read.get(res.value.link) == null);
            } else |err| switch (err) {
                error.ParserFailed => {},
                else => log.debug("Failed to parse feed: {} {}", .{ err, rest });
            }
        }

        log.debug("read/unread: {}/{}", .{ feeds_read.count(), unread });
        channel.put(.{
            .rss = .{
                .unread = unread,
                .read = feeds_read.count(),
            },
        });
    }
}

pub const Rss = struct {
    unread: usize,
    read: usize,
};

fn readIntoArrayList(dir: fs.Dir, file: []const u8, array_list: *std.ArrayList(u8)) ![]u8 {
    while (true) {
        const data = try dir.readFile(file, array_list.items);
        if (data.len < array_list.items.len)
            return data;

        try array_list.resize(array_list.items.len * 2);
    }
}

const FeedEntry = struct {
    timestamp: []const u8,
    title: []const u8,
    link: []const u8,
    content: []const u8,
    content_type: []const u8,
    id: []const u8,
    author: []const u8,
    enclosure: []const u8,
    category: []const u8,
};

const feedParser = mecha.map(FeedEntry, mecha.toStruct(FeedEntry), mecha.combine(.{
    mecha.manyN(
        mecha.many(
            mecha.ascii.not(mecha.oneOf(.{
                mecha.ascii.char('\t'),
                mecha.ascii.char('\n'),
            })),
            .{ .collect = false },
        ),
        9,
        .{ .separator = mecha.ascii.char('\t') },
    ),
    mecha.ascii.char('\n'),
}));
