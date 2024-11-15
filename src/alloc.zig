const limine = @import("limine");
const coreutils = @import("kern_coreutils.zig");
const main = @import("main.zig");
pub const MemoryMap = struct {
    map: *limine.MemoryMapResponse,
    pub fn fmt(self: *@This()) void {
        main.state.printer.color_preset(.Trace);
        const kinds: [8][]const u8 = .{"Usable", "Reserved", "ACPI Reclaimable", "ACPI NVS", "Bad Memory", "Bootloader Reclaimable", "Kernel Code", "Framebuffer"};
        for (self.map.entries()) |entry| {
            main.state.printer.print("Base: ");
            main.state.printer.print(&coreutils.FormatU64Hex(entry.base));
            main.state.printer.print("\n Length: ");
            main.state.printer.print(&coreutils.FormatU64Hex(entry.length));
            main.state.printer.print("\n Kind: ");
            main.state.printer.print(kinds[@intFromEnum(entry.kind)]);
            main.state.printer.print("\n\n");
        }
    }
};
pub const FrameAlloc = struct {

};
