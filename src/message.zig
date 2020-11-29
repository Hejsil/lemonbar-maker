const datetime = @import("datetime");
const producer = @import("producer.zig");

pub const Message = union(enum) {
    date: datetime.Datetime,
    mem: producer.Mem,
    cpu: producer.Cpu,
    rss: producer.Rss,
    mail: producer.Mail,
    bspwm: producer.Bspwm,
};
