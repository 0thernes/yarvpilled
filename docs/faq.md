# FAQ

### Is there any machine-learning model in here?
No. There are no weights, no neural nets and no ML libraries. Each brain is a Ruby method
compiled to YARV bytecode, and "learning" happens only through mutation and selection across
generations (genetic programming).

### Are the brains really executed as YARV bytecode?
Yes. Every tick, every living creature calls its species' `think(fa, fl, fr, en, cr, ag)`,
which is a `define_method`'d lambda loaded from `RubyVM::InstructionSequence#to_binary`. The
disasm panel shows `RubyVM::InstructionSequence.of(method).disasm` for the live method. Under
`--yjit`, hot brains get JIT-compiled like any other Ruby code.

### Why is Rust / asm not faster than C?
Two reasons. First, once the world loop is native, about 70% of each tick is YARV running the
brains and about 13% is compiling new genomes, so the world is only about 15% of the time.
Second, on the kernel alone, gcc -O3 already produces tight scalar code for this pointer-chasing
spatial-hash loop. The hand-written asm ties it, and the Rust port is slower: in the recorded
kernel-only medians it is 11% behind C and 17% behind asm. Bounds checks are the likely cause, but this hasn't been
profiled further. See
[bench.md](bench.md).

### Why isn't the asm SIMD?
The hot loop walks a linked list per grid cell (`ghead` / `gnext`), so there are no contiguous
lanes to vectorize without changing the data structure. Changing it would break bit-identity
with the other backends. The asm uses scalar SSE2 and replaces `idiv` grid wrapping with
`cmov`.

### Does it work on Windows?
Yes, through the pure-Ruby fallback. Install RubyInstaller **with DevKit**. `rake compile`
enables the DevKit's MSYS2 toolchain and tries to build the C extension (no asm, no Rust on
Windows). If that fails, it prints a warning and everything runs in pure Ruby. On the author's
Windows 11 PC (Ruby 3.4.9, pure Ruby) the whole test suite passes and `tools/reproduce.rb` matches every
recorded number bit for bit. Browser mode's server also runs there (with an SSE client
attached, the tick count kept rising past 500 through the Ractor votes); how the page and the
TUI (Windows Terminal) look has not been checked. `--video` needs `ffmpeg` on PATH. CI has an
informational Windows job; reports are welcome.

### Do I need YJIT?
No, but it helps the brains a lot (about 1.9x end to end in pure Ruby). Check
`ruby --yjit -v`. If your Ruby wasn't built with YJIT, the YJIT tiers are left out of the
benchmark.

### Is the selection result real or just noise?
See [control.md](control.md). In the pre-registered run (20 seeds per arm), against a
random-drift null model with the same seeds, selected populations forage better (+13%, Holm
p = 8.0e-04) and survive better (+30%, Holm p = 3.6e-04) in a common-garden assay. They also
carry much shorter bytecode. Caveats: one arena, 4000 ticks (about 10-15 generations). The
earlier 8-seed pilot is in [control_pilot.md](control_pilot.md).

### Why are runs with events on not exactly reproducible?
Ractor expert votes and GC timings depend on thread scheduling and the heap, so with events
on, two runs with the same seed can diverge after the first vote. Benchmarks and the control
experiment run with events off, and those runs are deterministic (see the benchmark checksum).

### Is the browser server safe to expose?
It binds to `127.0.0.1` by default. It's a tiny demo server with no auth. Pass `--bind=0.0.0.0`
only on a trusted network.
