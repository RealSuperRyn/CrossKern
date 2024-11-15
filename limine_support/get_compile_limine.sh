# Check if required commands are installed.
echo -e "Required install: git, make, grep, sed, awk, gzip, and nasm."
if ! command -v git &> /dev/null; then echo "Please install git."; exit 1; fi
if ! command -v make &> /dev/null; then echo "Please install make."; exit 1; fi
if ! command -v grep &> /dev/null; then echo "Please install grep."; exit 1; fi
if ! command -v sed &> /dev/null; then echo "Please install sed."; exit 1; fi
if ! command -v awk &> /dev/null; then echo "Please install awk."; exit 1; fi
if ! command -v gzip &> /dev/null; then echo "Please install gzip."; exit 1; fi
if ! command -v nasm &> /dev/null; then echo "Please install nasm."; exit 1; fi
#Clone limine and compile.
cd limine_support
if [[ ! -d "$(pwd)/limine" ]]; then
  git clone https://github.com/limine-bootloader/limine
  cd limine
  #Set Zig as the C compiler so that the user doesn't have to install any other compilers
  export CC="zig cc"
  ./bootstrap
  ./configure --enable-uefi-x86_64
  make -j$(nproc)
  #Prepare esp
  cd ..
fi
mkdir -p ./esp/EFI/BOOT/
cp ./limine/bin/BOOTX64.EFI ./esp/EFI/BOOT/
#Place limine configuration
cp ./limine.conf ./esp/
cp ../zig-out/bin/crosskern ./esp/
