const limine = @import("limine");
const interrupts = @import("interrupts.zig");
const main = @import("main.zig");
const alloc = @import("alloc.zig");
//TODO: Once the file grows too massive, split it into categorized chunks.
//Hodgepodge file.


pub const KernelState = struct {
    fb: ?*limine.Framebuffer = null, //TODO: Retain all bootloader-provided framebuffers
    idt: interrupts.IDT = .{},
    tss: interrupts.TSS = .{},
    gdt: interrupts.GDT = .{},
    printer: Printer = .{},
    memmap: ?alloc.MemoryMap = null,
    pub fn putpixel(self: *@This(), color: u32, x: u32, y: u32) void {
        if (self.fb) |fb| {
            if (fb.width == 0) {//(fb.width * fb.height > @as(u64, y) * fb.width + @as(u64, x)) {
                return; //Not letting a misplaced pixel bring down the system.
            } else {
                @as(*u32, @ptrCast(@alignCast((fb.address + (y * fb.width + x)*4)))).* = color;
            }
        }
    }
    pub fn fill(self: *@This(), color: u32) void {
        if (self.fb) |fb| {
            for (0..fb.height) |j| {
                for (0..fb.width) |i| {
                    @as(*u32, @ptrCast(@alignCast((fb.address + (j * fb.width + i)*4)))).* = color;
                }
            }
        }
    }
    pub fn fmt(self: *@This()) void {
        self.printer.color_preset(.Trace);
        self.printer.print("--KERNEL STATE--\nFramebuffer Pointer: ");
        self.printer.print(&FormatU64Hex(@intFromPtr(&self.fb)));
        self.printer.print("\nIDT Pointer:");
        self.printer.print(&FormatU64Hex(@intFromPtr(&self.idt)));
        self.printer.print("\nGDT Pointer:");
        self.printer.print(&FormatU64Hex(@intFromPtr(&self.gdt) | self.gdt.len*8-1));
        self.gdt.fmt();
        self.printer.print("\nPrinter Pointer:");
        self.printer.print(&FormatU64Hex(@intFromPtr(&self.printer)));
        self.printer.print("\nMemory Map Pointer:");
        self.printer.print(&FormatU64Hex(@intFromPtr(&self.memmap)));
        self.printer.print("\n");
    }
};
pub const FONT: []const u8 = @embedFile("font.dci");
pub const DCIImage = struct {
    width: u32 = 128,
    height: u32 = 112,
    data: [*]const u8 = FONT.ptr + 8,
    //pub fn from_raw(input: []const u8) DCIImage {
    //    hcf();
    //    return .{
    //        .width = @as(*u32, @ptrCast(@constCast(@alignCast(input.ptr)))).*,
    //        .height = @as(*u32, @ptrCast(@constCast(@alignCast(input.ptr + 4)))).*,
    //        .data = input.ptr + 8
    //    };
    //}
    pub fn get_index(index: usize) struct { byte: usize, bit: u3} {
        return .{.byte = (index & (~@as(usize, 7))) >> 3, .bit = @truncate(index & 7)};
    }
};
pub const Printer = struct {
    x: u16 = 0,
    y: u16 = 0,
    bgcol: u32 = 0x00000000,
    fgcol: u32 = 0x00FFFFFF,
    font: DCIImage = .{},
    pub fn printc(self: *@This(), text: []const u8, colors: ColorPreset) void {
        self.color_preset(colors);
        self.print(text);
    }
    pub fn print(self: *@This(), text: []const u8) void {
        if (main.state.fb) |fb| {
            for (text) |char| {
                if (char <= 32) {
                    if (char == 0x0A) {
                        self.y += 8; //TODO: Define glyph dimensions as constants in this struct
                        self.x = 0;
                    }
                    if (char == 32) {
                        if (self.x + 7 >= fb.width) {
                            self.y += 8;
                            self.x = 0;
                        } else {self.x += 7;}
                    }
                } else {

                    blit_char(&self.font, self.x, self.y, char, self.bgcol, self.fgcol);
                    if (self.x + 7 >= fb.width) {
                        self.y += 8;
                        self.x = 0;
                    } else {self.x += 7;}
                }
            }
        }
    }
    pub fn color_preset(self: *@This(), preset: ColorPreset) void {
        switch (preset) {
            .Default => {
                self.bgcol = 0x00222233;
                self.fgcol = 0x00AAAAAA;
            },
            .Fatal => {
                self.bgcol = 0x00000000;
                self.fgcol = 0x00FF4400;
            },
            .Error => {
                self.bgcol = 0x00772233;
                self.fgcol = 0x00FFAAAA;
            },
            .Warn => {
                self.bgcol = 0x00888800;
                self.fgcol = 0x00CCCCAA;
            },
            .Trace => {
                self.bgcol = 0x002222AA;
                self.fgcol = 0x00AAAAFF;
            },
            .Info => {
                self.bgcol = 0x00222233;
                self.fgcol = 0x00AAAAFF;
            },
            .Success => {
                self.bgcol = 0x00227733;
                self.fgcol = 0x00AAFFAA;
            }
        }
    }
    pub fn clear(self: *@This(), colors: ColorPreset) void {
        self.color_preset(colors);
        main.state.fill(self.bgcol);
    }
};

pub const ColorPreset = enum {
    Default, Fatal, Error, Warn, Trace, Info, Success,
};

pub fn get_char(font: *DCIImage, id: u8) [8]u8 {

    var bytes: [8]u8 = .{0} ** 8;
    if (id <= 32) {return bytes;}
    const c = id - 32;
    const indices_first_char = DCIImage.get_index((c / 16) * font.width * 8 + ((c & 15) * 8));
    var j: usize = 0;
    for (0..7) |i| {
        bytes[i] = font.data[indices_first_char.byte + 16 * j];
        j += 1;
    }
    return bytes;
}
pub fn blit_char(font: *DCIImage, x: u16, y: u16, id: u8, bgcolor: u32, fgcolor: u32) void {
    const glyph = get_char(font, id);
    var i: u16 = 0;
    for (glyph) |g| {
        for (0..7) |j| {

            if ((g & (@as(u8, 1) << @truncate(j))) > 0) {
                main.state.putpixel(fgcolor, x + @as(u32, @intCast(j)), y + i);
            } else {
                main.state.putpixel(bgcolor, x + @as(u32, @intCast(j)), y + i);
            }
        }
        i += 1;
    }
}

pub fn hcf() noreturn {
    main.state.printer.printc("End of execution", .Fatal);
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}

const splitbyte align(1) = struct {
    lower: u4,
    upper: u4,
    pub fn cast_byte(b: u8) splitbyte {
        return .{.lower = @truncate((b & 15)), .upper = @truncate((b >> 4)&15)};
    }
};

pub fn FormatU64Hex(input: u64) [18]u8 {
    const hexchars = "0123456789ABCDEF";
    const value: [8]u8 = @bitCast(@byteSwap(input));
    const prefix = "0x";
    var fmt: [16]u8 = .{48} ** 16;
    for (0..8) |i| {
        const split = splitbyte.cast_byte(value[i]);
        fmt[i*2] = hexchars[split.upper];
        fmt[i*2+1] = hexchars[split.lower];
    }
    const ret: [18]u8 = (prefix ++ fmt).*;
    return ret;
}

pub const Bitfield = struct {
    inner: [16]u8,
    top: u8,
    pub fn get_bits_of_num(num: anytype, a: u8, b: u8) Bitfield {
        comptime {
            const assert = @import("std").debug.assert; //standard lib import #1
            const T = @TypeOf(num);
            assert(@typeInfo(T) == .int and @typeInfo(T).int.signedness == .unsigned);
        }
        return .{.inner = @as([16]u8, @bitReverse(@as(u128, num))), .top = 127}.get_bits(a, b);
    }
    pub fn get_bits(self: *@This(), a: u8, b: u8) Bitfield {
        const lower = if (a<b) {a;} else {b;};
        const upper = if (a>b) {a;} else {b;};
        //var retfield: Bitfield = .{};
        for (lower..upper) |i| {
            self.get_bit(i);
        }
    }
    pub inline fn get_bit(self: *@This(), bit: u8) bool {
        return !(((self.inner[bit >> 3] >> (bit & 7)) & 1) == 0);
    }
    //pub inline fn set_bit(self: *@This(), bit: u8, state: bool) void {
    //    self.inner[bit >> 3] |= 1 << (bit & 7)
    //}
};

pub const HeapKey = struct {
    alloc: *fn(alignment: usize, size: usize) ?[*]u8,
    realloc: *fn(obj: [*]u8, newsize: usize) ?[*]u8,
    dealloc: *fn(obj: [*]u8) void,
};
pub const GenericBytecodeEngine = struct {
    hkey: HeapKey,
    func_state: [*]u8,
    position: usize,
    bclen: usize,
    bytecode: [*]u8,
    functions: [256]*fn(gbe: *GenericBytecodeEngine) void,
    pub fn Iterate(self: *@This()) void {
        while (self.position < self.bclen) {
            self.functions[self.bytecode[self.position]](self);
        }
    }
};
