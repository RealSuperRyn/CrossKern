const limine = @import("limine");
const coreutils = @import("kern_coreutils.zig");
const interrupts = @import("interrupts.zig");
const handlers = @import("handlers.zig");
const hcf = coreutils.hcf;

pub export var base_revision: limine.BaseRevision = .{ .revision = 2 };
pub export var framebuffer_request: limine.FramebufferRequest = .{};
pub export var paging_request: limine.PagingModeRequest = .{ .mode = limine.PagingMode.four_level, .flags = 0};
pub export var mmap_request: limine.MemoryMapRequest = .{};


const STACK_KIB = 32;

export var stack: [STACK_KIB*1024]u8 align(16) linksection(".bss") = undefined;
export var stack_top = (&stack).ptr + stack.len;

export fn _start() callconv(.Naked) noreturn {
	asm volatile(
		\\mov stack_top, %rsp
		\\call kernel_entry
		\\cli
	);
	while (true) {
		asm volatile ("hlt");
	}
}

pub var state: coreutils.KernelState = .{}; //TODO: Spinlock + Mutex

export fn kernel_entry() void {
	if (!base_revision.is_supported()) {
		hcf(); //If it isn't supported, we got none of the boot resources we needed, and cannot continue.
	}

	if (framebuffer_request.response) |framebuffer_response| {
		if (framebuffer_response.framebuffer_count < 1) {
			state.fb = null;
		} else {
			state.fb = framebuffer_response.framebuffers()[0];
		}
	}
	state.printer.clear(.Default);
	state.printer.printc("Loading IDT\n", .Info);
	handlers.init_idt();
	state.printer.printc("Loading GDT\n", .Info);
	state.gdt.add_entry(interrupts.GDT_DESC_KERNELDATA, null);
	var doublefaultstack: [4096]u8 = undefined;
	state.tss.set_pst((&doublefaultstack).ptr, 0);
	state.gdt.add_tss(&state.tss);
	state.fmt();
	state.gdt.activate();
	state.printer.printc("Acquiring the memory map\n", .Info);
	if (mmap_request.response) |mmap_response| {
		state.memmap = .{.map = mmap_response};
		state.memmap.?.fmt();
	}
	hcf(); //TODO: enter mainloop
}

fn kernel_mainloop() void {

}


