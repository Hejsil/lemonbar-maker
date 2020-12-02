const datetime = @import("datetime");
const producer = @import("producer.zig");

pub const Message = union(enum) {
    date: datetime.Datetime,
    mem: Memory,
    cpu: Cpu,
    mail: News,
    rss: News,
    workspace: Workspace,
};

pub const Workspace = struct {
    id: usize,
    monitor_id: usize,
    flags: Flags,

    pub const Flags = packed struct {
        focused: bool,
        occupied: bool,
    };
};

pub const News = struct {
    read: usize,
    unread: usize,
};

pub const Cpu = struct {
    id: usize,
    user: usize,
    sys: usize,
    idle: usize,
};

pub const Memory = struct {
    total: usize,
    free: usize,
    available: usize,
};
