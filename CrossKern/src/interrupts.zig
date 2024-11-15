const main = @import("main.zig");
const coreutils = @import("kern_coreutils.zig");

pub const IDTEntryOptions = struct {
    ss: SegmentSelector = .{},
    bb: IDTEntryOptionsBitfield = .{}
};

pub const SegmentSelector = packed struct {
    RequestedPrivilegeLevel: u2 = 0, //Default: Kernel mode
    TI: u1 = 0,                      //I'm assuming 0 is a sane default.
    Index: u13 = 0,                  //Index 0, akin to null pointers being defined as 0.
};

pub const IDTEntryOptionsBitfield = packed struct {
    ISTIndex: u3 = 0,
    None: u4 = 0,
    Gate: u1 = 1,
    Checksum: u4 = 0b1110,
    DPL: u2 = 0,
    Present: u1 = 1,
    pub fn new() IDTEntryOptionsBitfield {
        return .{};
    }
    pub fn toggle_interrupts(self: *@This(), toggle: bool) void {
        self.Gate = toggle;
    }
};

pub const IDTEntry = struct {
    LowPointer: u16 = 0,
    options: IDTEntryOptions = .{},
    HighPointer: [3]u16 = .{0, 0, 0},
    Reserved: u32 = 0,
    pub fn SetPointer(self: *@This(), ptr: u64) void {
        const splitptr: [4]u16 = @bitCast(ptr);
        self.LowPointer = splitptr[0];
        self.HighPointer = .{splitptr[1], splitptr[2], splitptr[3]};
    }
};

pub const IDT = struct {
    inner: [256]IDTEntry = .{.{}} ** 256,
    pub fn SetEntry(self: *@This(), entryid: u8, entrycontents: IDTEntry) void {
        self.inner[entryid] = entrycontents;
    }
};


pub const TSS = struct {
    none0: u32 = 0,
    PST: [3][*]u8 = .{undefined} ** 3,
    none1: u64 = 0,
    IST: [7]u64 = .{0} ** 7,
    none2: u64 = 0,
    none3: u64 = 0,
    IOMapBaseAddr: u16 = 0,
    //Past last entry, can have own stuff here now
    pub inline fn set_pst(self: *@This(), stack: [*]u8, idx: u64) void {
        self.PST[idx] = stack;
    }
};

//Flags for GDT descriptors
pub const GDT_ACCESSED: u64 = 1 << 40;
pub const GDT_WRITABLE: u64 = 1 << 41;
pub const GDT_CONFORMING: u64 = 1 << 42;
pub const GDT_EXECUTABLE: u64 = 1 << 43;
pub const GDT_USER_SEGMENT: u64 = 1 << 44;
pub const GDT_RING3: u64 = 3 << 45;
pub const GDT_PRESENT: u64 = 1 << 47;
pub const GDT_AVAILABLE: u64 = 1 << 52;
pub const GDT_LONG_MODE: u64 = 1 << 53;
pub const GDT_DEFAULT_SIZE: u64 = 1 << 54;
pub const GDT_GRANULARITY: u64 = 1 << 55;

pub const GDT_LIMIT_0_15: u64 = 0xFFFF;
pub const GDT_LIMIT_16_19: u64 = 0xF;
pub const GDT_BASE_0_23: u64 = 0xFFFFFF << 16;
pub const GDT_BASE_24_31: u64 = 0xFF << 56;

pub const GDT_DESC_COMMON: u64 = GDT_PRESENT | GDT_WRITABLE | GDT_ACCESSED | GDT_LIMIT_0_15 | GDT_LIMIT_16_19 | GDT_GRANULARITY;

pub const GDT_DESC_KERNELDATA: u64 = GDT_DESC_COMMON | GDT_DEFAULT_SIZE | GDT_LONG_MODE;

pub const gdt_preheap_size = 8; //TODO: Reinit GDT on KOS init
pub const GDT = struct {
    inner: [gdt_preheap_size]u64 = .{0} ** gdt_preheap_size,
    len: u64 = gdt_preheap_size,
    top: u64 = 1,
    pub fn add_entry(self: *@This(), low: u64, high: ?u64) void {
        self.inner[self.top] = low; self.top += 1;
        if (high) |h| {
            self.inner[self.top] = h; self.top += 1;
        }
    }
    pub fn add_tss(self: *@This(), tss: *TSS) void {
        const tss_bits: u64 = @intFromPtr(tss);
        var low: u64 = GDT_PRESENT | GDT_AVAILABLE | GDT_LONG_MODE;
        //Set base
        low |= ((tss_bits & 0xFFFFFF) << 16);
        low |= ((tss_bits & (0xFF << 24)) << 32);
        //Set limit
        low |= @as(u64, @sizeOf(TSS) - 1);
        const high = tss_bits & (0xFFFFFFFF << 32);
        self.add_entry(low, high);
    }
    pub fn activate(self: *@This()) void {
        const gdtptr = @intFromPtr(self) | self.len*8-1;
        asm volatile(
            \\lgdt %[gdtptr]
            : : [gdtptr] "p" (gdtptr)
        );
        asm volatile(
            \\  mov %[dsel], %ds
            \\  mov %[dsel], %fs
            \\  mov %[dsel], %gs
            \\  mov %[dsel], %es
            \\  mov %[dsel], %ss
            :
            : [dsel] "rm" (0x10)
        );
        asm volatile(
            \\push $0x08
            \\lea 1f(%%rip), %%rax
            \\push %%rax
            \\.byte 0x48, 0xCB
            \\1:
        );
    }
    pub fn fmt(self: *@This()) void {
        main.state.printer.color_preset(.Trace);
        main.state.printer.print("-GDT Struct Info-\nPointer: ");
        main.state.printer.print(&coreutils.FormatU64Hex(@intFromPtr(self) | self.len*8-1));
        for (0..self.len-1) |i| {
            main.state.printer.print("\n");
            main.state.printer.print(&coreutils.FormatU64Hex(i));
            main.state.printer.print(": ");
            main.state.printer.print(&coreutils.FormatU64Hex(self.inner[i]));
        }
        main.state.printer.print("\n-End of Struct Info-\n");
    }
};

//"VI" here is shorthand for "Vector Index".
pub const DivideVI: u8 = 0;
pub const DebugVI: u8 = 1;
pub const NonMaskVI: u8 = 2;
pub const BreakpointVI: u8 = 3;
pub const OverflowVI: u8 = 4;
pub const BoundExceededVI: u8 = 5;
pub const InvalidOpcodeVI: u8 = 6;
pub const DeviceUnavailableVI: u8 = 7;
pub const DoubleFaultVI: u8 = 8;
//VI #9 is for a deprecated exception and is reserved.
pub const InvalidTSSVI: u8 = 10;
pub const SegmentNotPresentVI: u8 = 11;
pub const SegfaultVI: u8 = 12;
pub const GeneralProtectionFaultVI: u8 = 13;
pub const PageFaultVI: u8 = 14;
//VI #15 is reserved.
pub const x87FPVI: u8 = 16;
pub const AlignCheckVI: u8 = 17;
pub const MachineCheckVI: u8 = 18;
pub const SimdFPVI: u8 = 19;
pub const VirtualizationVI: u8 = 20;
pub const CPPEVI: u8 = 21;
//VI #22 to #27 are reserved.
pub const HVInjectionVI: u8 = 28;
pub const VMMCommVI: u8 = 29;
pub const SecurityVI: u8 = 30;
//VI #31 is reserved.
pub const UserIntOneVI: u8 = 32; //VI of the first user interrupt.


//pub const HandlerBody = fn (*ExceptionStackFrame) callconv(.Naked) noreturn;
pub const ExceptionStackFrame = struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rbp: u64,
    rsp: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    vector_num: u64,
    error_code: u64,
    instruction_pointer: u64,
    code_segment: u64,
    flags: u64,
    orig_rsp: u64,
    stack_segment: u64,
    pub fn print(self: *@This()) void {
        main.state.printer.bgcol = 0x00ff0000;
        const names = [22][]const u8{"R15", "R14", "R13", "R12", "R11", "R10", "R9", "R8", "RBP", "RSP", "RDI", "RSI", "RDX", "RCX", "RBX", "RAX", "ISR Vector", "Error Code", "RIP", "Code Segment", "Flags", "Stack Segment"};
        const vals = [22]u64{self.r15, self.r14, self.r13, self.r12, self.r11, self.r10, self.r9, self.r8, self.rbp, self.orig_rsp, self.rdi, self.rsi, self.rdx, self.rcx, self.rbx, self.rax, self.vector_num, self.error_code, self.instruction_pointer, self.code_segment, self.flags, self.stack_segment};
        for (0..21) |i| {
            const message = coreutils.FormatU64Hex(vals[i]);
            main.state.printer.print(names[i]);
            main.state.printer.print(": ");
            main.state.printer.print(&message);
            main.state.printer.print("\n");
        }

    }
};
