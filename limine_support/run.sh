cd limine_support
qemu-system-x86_64 -d int --no-reboot --no-shutdown -drive if=pflash,format=raw,readonly=on,file=../OVMF_CODE.fd -drive if=pflash,format=raw,readonly=on,file=../OVMF_VARS.fd -drive format=raw,file=fat:rw:esp
