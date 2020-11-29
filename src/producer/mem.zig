const std = @import("std");
const mecha = @import("mecha");

const event = std.event;
const fs = std.fs;

const Message = @import("../message.zig").Message;

pub fn mem(channel: *event.Channel(Message)) void {
    const loop = event.Loop.instance.?;
    const cwd = fs.cwd();

    // On my system, `cat /proc/meminfo | wc -c` gives 1419, so this buffer
    // should be enough to hold all data read from meminfo.
    var buf: [1024 * 10]u8 = undefined;

    while (true) {
        const content = cwd.readFile("/proc/meminfo", &buf) catch continue;
        const result = parser(content) orelse continue;
        channel.put(.{ .mem = result.value });

        loop.sleep(std.time.ns_per_s);
    }
}

pub const Mem = struct {
    mem_total: usize,
    mem_free: usize,
    mem_available: usize,
    buffers: usize,
    cached: usize,
    swap_cached: usize,
    active: usize,
    inactive: usize,
    active_anon: usize,
    inactive_anon: usize,
    active_file: usize,
    inactive_file: usize,
    unevictable: usize,
    mlocked: usize,
    swap_total: usize,
    swap_free: usize,
    dirty: usize,
    writeback: usize,
    anon_pages: usize,
    mapped: usize,
    shmem: usize,
    kreclaimable: usize,
    slab: usize,
    sreclaimable: usize,
    sunreclaim: usize,
    kernel_stack: usize,
    page_tables: usize,
    nfs_unstable: usize,
    bounce: usize,
    writeback_tmp: usize,
    commit_limit: usize,
    committed_as: usize,
    vmalloc_total: usize,
    vmalloc_used: usize,
    vmalloc_chunk: usize,
    percpu: usize,
    hardware_corrupted: usize,
    anon_huge_pages: usize,
    shmem_huge_pages: usize,
    shmem_pmd_mapped: usize,
    file_huge_pages: usize,
    file_pmd_mapped: usize,
    huge_pages_total: usize,
    huge_pages_free: usize,
    huge_pages_rsvd: usize,
    huge_pages_surp: usize,
    hugepagesize: usize,
    hugetlb: usize,
    direct_map4k: usize,
    direct_map2m: usize,
    direct_map1g: usize,

    fn from(t: anytype) ?Mem {
        return Mem{
            .mem_total = t[0],
            .mem_free = t[1],
            .mem_available = t[2],
            .buffers = t[3],
            .cached = t[4],
            .swap_cached = t[5],
            .active = t[6],
            .inactive = t[7],
            .active_anon = t[8],
            .inactive_anon = t[9],
            .active_file = t[10],
            .inactive_file = t[11],
            .unevictable = t[12],
            .mlocked = t[13],
            .swap_total = t[14],
            .swap_free = t[15],
            .dirty = t[16],
            .writeback = t[17],
            .anon_pages = t[18],
            .mapped = t[19],
            .shmem = t[20],
            .kreclaimable = t[21],
            .slab = t[22],
            .sreclaimable = t[23],
            .sunreclaim = t[24],
            .kernel_stack = t[25],
            .page_tables = t[26],
            .nfs_unstable = t[27],
            .bounce = t[28],
            .writeback_tmp = t[29],
            .commit_limit = t[30],
            .committed_as = t[31],
            .vmalloc_total = t[32],
            .vmalloc_used = t[33],
            .vmalloc_chunk = t[34],
            .percpu = t[35],
            .hardware_corrupted = t[36],
            .anon_huge_pages = t[37],
            .shmem_huge_pages = t[38],
            .shmem_pmd_mapped = t[39],
            .file_huge_pages = t[40],
            .file_pmd_mapped = t[41],
            .huge_pages_total = t[42],
            .huge_pages_free = t[43],
            .huge_pages_rsvd = t[44],
            .huge_pages_surp = t[45],
            .hugepagesize = t[46],
            .hugetlb = t[47],
            .direct_map4k = t[48],
            .direct_map2m = t[49],
            .direct_map1g = t[50],
        };
    }
};

const parser = blk: {
    @setEvalBranchQuota(1000000000);

    break :blk mecha.convert(Mem, Mem.from, mecha.combine(.{
        field("MemTotal"),
        field("MemFree"),
        field("MemAvailable"),
        field("Buffers"),
        field("Cached"),
        field("SwapCached"),
        field("Active"),
        field("Inactive"),
        field("Active(anon)"),
        field("Inactive(anon)"),
        field("Active(file)"),
        field("Inactive(file)"),
        field("Unevictable"),
        field("Mlocked"),
        field("SwapTotal"),
        field("SwapFree"),
        field("Dirty"),
        field("Writeback"),
        field("AnonPages"),
        field("Mapped"),
        field("Shmem"),
        field("KReclaimable"),
        field("Slab"),
        field("SReclaimable"),
        field("SUnreclaim"),
        field("KernelStack"),
        field("PageTables"),
        field("NFS_Unstable"),
        field("Bounce"),
        field("WritebackTmp"),
        field("CommitLimit"),
        field("Committed_AS"),
        field("VmallocTotal"),
        field("VmallocUsed"),
        field("VmallocChunk"),
        field("Percpu"),
        field("HardwareCorrupted"),
        field("AnonHugePages"),
        field("ShmemHugePages"),
        field("ShmemPmdMapped"),
        field("FileHugePages"),
        field("FilePmdMapped"),
        field("HugePages_Total"),
        field("HugePages_Free"),
        field("HugePages_Rsvd"),
        field("HugePages_Surp"),
        field("Hugepagesize"),
        field("Hugetlb"),
        field("DirectMap4k"),
        field("DirectMap2M"),
        field("DirectMap1G"),
    }));
};

fn field(comptime name: []const u8) mecha.Parser(usize) {
    return mecha.combine(.{
        mecha.string(name ++ ":"),
        mecha.discard(mecha.many(mecha.char(' '))),
        mecha.int(usize, 10),
        mecha.discard(mecha.opt(mecha.string(" kB"))),
        mecha.char('\n'),
    });
}
