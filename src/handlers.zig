const interrupts = @import("interrupts.zig");
const coreutils = @import("kern_coreutils.zig");
const main = @import("main.zig");

pub fn init_idt() void {
    var masterhandler: interrupts.IDTEntry = .{};
    masterhandler.SetPointer(@intFromPtr(&MasterStub));
    for (0..31) |i| {
        main.state.idt.SetEntry(@truncate(i), masterhandler);
    }
    const idtr = &main.state.idt;
    asm volatile(
        \\lidt %[idtr]
        :
        : [idtr] "m" (idtr)
    );
    main.state.printer.printc("IDT loaded.\n", .Success);
}

export fn MasterStub() callconv(.Naked) noreturn {
    asm volatile(
        \\push %rax
        \\push %rbx
        \\push %rcx
        \\push %rdx
        \\push %rsi
        \\push %rdi
        \\push %rsp
        \\push %rbp
        \\push %r8
        \\push %r9
        \\push %r10
        \\push %r11
        \\push %r12
        \\push %r13
        \\push %r14
        \\push %r15
        \\mov %rsp, %rdi
        \\call MasterHandler
        \\pop %r15
        \\pop %r14
        \\pop %r13
        \\pop %r12
        \\pop %r11
        \\pop %r10
        \\pop %r9
        \\pop %r8
        \\pop %rbp
        \\pop %rsp
        \\pop %rdi
        \\pop %rsi
        \\pop %rdx
        \\pop %rcx
        \\pop %rbx
        \\pop %rax
        \\iretq
    );
}

export fn MasterHandler() void {
    const StackFrame = asm volatile(""
        : [ret] "={rdi}" (-> *interrupts.ExceptionStackFrame)
    );
    StackFrame.print();
    main.state.printer.print("--END STACK FRAME--");
}
