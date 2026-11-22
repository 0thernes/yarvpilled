/*
 * crowd_x86_64.S -- hand-written x86-64 (SysV, SSE2 scalar double) version
 * of yp_c_crowd() in kernel_c.c: count neighbours of creature i within
 * CROWD_R on a torus, scanning the 3x3 spatial-hash neighbourhood.
 *
 *   int32_t yp_asm_crowd(const CrowdCtx *c /rdi/, int32_t i /esi/)
 *
 * Bit-identical to the C version: same mulsd/addsd/subsd order, no FMA,
 * same truncating cvttsd2si; the grid wrap uses cmov instead of idiv
 * (exactly equal to C's % for the in-range operands, see comment below).
 * Plain scalar code: the inner loop chases a linked list, so there is no
 * honest SIMD win here; this is about hand-scheduling the hot loop.
 *
 * CrowdCtx offsets: x 0, y 8, ghead 16, gnext 24, gw 32, gh 36,
 *                   gcell 40, w 48, h 56, r2 64
 */
        .text
        .globl  yp_asm_crowd
        .type   yp_asm_crowd, @function
yp_asm_crowd:
        pushq   %rbx
        pushq   %rbp
        pushq   %r12
        pushq   %r13
        pushq   %r14
        pushq   %r15
        movq    %rdi, %r15              /* r15 = ctx */
        movl    %esi, %r14d             /* r14d = i */
        movq    0(%r15), %r8            /* r8  = x */
        movq    8(%r15), %r9            /* r9  = y */
        movslq  %esi, %rax
        movsd   (%r8,%rax,8), %xmm8     /* px */
        movsd   (%r9,%rax,8), %xmm9     /* py */
        movsd   48(%r15), %xmm10        /* W */
        movsd   56(%r15), %xmm11        /* H */
        movsd   64(%r15), %xmm12        /* r2 */
        movsd   %xmm10, %xmm13
        mulsd   .Lhalf(%rip), %xmm13    /* W/2 (exact) */
        movsd   %xmm11, %xmm14
        mulsd   .Lhalf(%rip), %xmm14    /* H/2 (exact) */
        movapd  %xmm8, %xmm0
        divsd   40(%r15), %xmm0
        cvttsd2si %xmm0, %r12d          /* gx */
        movapd  %xmm9, %xmm0
        divsd   40(%r15), %xmm0
        cvttsd2si %xmm0, %r13d          /* gy */
        movapd  %xmm13, %xmm15
        xorpd   .Lsign(%rip), %xmm15    /* -W/2, hoisted */
        movapd  %xmm14, %xmm7
        xorpd   .Lsign(%rip), %xmm7     /* -H/2, hoisted */
        movl    32(%r15), %edi          /* edi = gw */
        movq    16(%r15), %rdx          /* rdx = ghead */
        movq    24(%r15), %rsi          /* rsi = gnext */
        xorl    %ebx, %ebx              /* count */
        movl    $-1, %ebp               /* oy */
.Loy:
        /* cy = (gy + oy + gh) % gh without idiv: gy is in [0, gh), so
         * t = gy+oy is in [-1, gh]; add gh if t < 0, subtract gh if t >= gh.
         * That equals C's % for every operand that can occur here. */
        leal    (%r13,%rbp), %eax       /* t = gy + oy */
        movl    36(%r15), %ecx
        addl    %eax, %ecx              /* t + gh */
        testl   %eax, %eax
        cmovs   %ecx, %eax              /* t < 0  -> t + gh */
        movl    %eax, %ecx
        subl    36(%r15), %ecx          /* t - gh */
        cmpl    36(%r15), %eax
        cmovge  %ecx, %eax              /* t >= gh -> t - gh */
        imull   %edi, %eax
        movl    %eax, %r10d             /* r10d = cy * gw */
        movl    $-1, %r11d              /* ox */
.Lox:
        leal    (%r12,%r11), %eax       /* t = gx + ox, in [-1, gw] */
        leal    (%rax,%rdi), %ecx
        testl   %eax, %eax
        cmovs   %ecx, %eax
        movl    %eax, %ecx
        subl    %edi, %ecx
        cmpl    %edi, %eax
        cmovge  %ecx, %eax              /* cx */
        addl    %r10d, %eax
        cltq
        movslq  (%rdx,%rax,4), %rax     /* j = ghead[cell] */
.Lj:
        testq   %rax, %rax
        js      .Lnext_cell
        cmpl    %r14d, %eax
        je      .Ladvance
        /* dx = tdelta(px, x[j], W) */
        movsd   (%r8,%rax,8), %xmm0
        subsd   %xmm8, %xmm0
        ucomisd %xmm13, %xmm0           /* d > W/2 ? */
        jbe     1f
        subsd   %xmm10, %xmm0
1:      ucomisd %xmm0, %xmm15           /* -W/2 > d ? */
        jbe     2f
        addsd   %xmm10, %xmm0
2:      /* dy = tdelta(py, y[j], H) */
        movsd   (%r9,%rax,8), %xmm1
        subsd   %xmm9, %xmm1
        ucomisd %xmm14, %xmm1
        jbe     3f
        subsd   %xmm11, %xmm1
3:      ucomisd %xmm1, %xmm7
        jbe     4f
        addsd   %xmm11, %xmm1
4:      mulsd   %xmm0, %xmm0
        mulsd   %xmm1, %xmm1
        addsd   %xmm1, %xmm0            /* dx*dx + dy*dy */
        ucomisd %xmm0, %xmm12           /* r2 > d2 ? */
        jbe     .Ladvance
        incl    %ebx
.Ladvance:
        movslq  (%rsi,%rax,4), %rax     /* j = gnext[j] */
        jmp     .Lj
.Lnext_cell:
        incl    %r11d
        cmpl    $1, %r11d
        jle     .Lox
        incl    %ebp
        cmpl    $1, %ebp
        jle     .Loy
        movl    %ebx, %eax
        popq    %r15
        popq    %r14
        popq    %r13
        popq    %r12
        popq    %rbp
        popq    %rbx
        ret
        .size   yp_asm_crowd, .-yp_asm_crowd

        .section .rodata
        .align  16
.Lhalf: .double 0.5, 0.5
.Lsign: .quad   0x8000000000000000, 0x8000000000000000
        .section .note.GNU-stack,"",@progbits
