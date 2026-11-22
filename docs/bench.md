# YARVPILLED benchmark

ruby 3.4.7 | Intel(R) Xeon(R) Processor | 8 cpus | seed 11 | 2000 ticks | 5 runs per tier, each a fresh process | values are **median (min-max)**

<details><summary>Hardware and toolchain (captured at run time)</summary>

| key | value |
|---|---|
| cpu | Intel(R) Xeon(R) Processor |
| logical_cpus | 8 |
| cpu_flags_avx2 | true |
| cpu_mhz | 2400.0 |
| governor |  |
| mem_gb | 15.6 |
| os | linux |
| kernel | Linux 6.12.113+ |
| virtualization | container-other |
| loadavg_at_start | 4.87 4.15 3.36 |
| ruby | ruby 3.4.7 (2025-10-08 revision 7a5688e2a2) +PRISM [x86_64-linux] |
| yjit_available | true |
| cc | gcc (Debian 14.2.0-19) 14.2.0 |
| rustc | rustc 1.85.1 (4eb161250 2025-03-15) (built from a source tarball) |
| git_commit | a6aed905b267 |
| git_dirty | true |
| date_utc | 2026-11-22T23:12:17Z |

</details>

## Full simulation (brains + world)

| tier | creatures/sec | generations/sec | ticks/sec | vs pure Ruby | time in brains (YARV think) | time compiling births (mutate+ISeq) | time in world (sense+act) | spread | checksum |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| pure Ruby interpreter | 74,747 (68,142-81,448) | 1.97 (1.80-2.15) | 438 (400-478) | 1.00x | 18% | 3% | 80% | 17.8% | `557-9-178-1263170-160` |
| pure Ruby + YJIT | 139,866 (127,136-144,177) | 3.69 (3.35-3.80) | 820 (745-845) | 1.87x | 32% | 6% | 62% | 12.2% | `557-9-178-1263170-160` |
| C + YJIT | 243,619 (202,250-276,294) | 6.43 (5.34-7.29) | 1,428 (1,186-1,620) | 3.26x | 72% | 13% | 14% | 30.4% | `557-9-178-1263170-160` |
| Rust + YJIT | 251,895 (233,588-263,868) | 6.65 (6.16-6.96) | 1,477 (1,370-1,547) | 3.37x | 70% | 13% | 16% | 12.0% | `557-9-178-1263170-160` |
| asm + YJIT | 262,779 (257,459-282,998) | 6.93 (6.79-7.47) | 1,541 (1,510-1,659) | 3.52x | 72% | 13% | 14% | 9.7% | `557-9-178-1263170-160` |
| C, interpreter (extra) | 223,338 (179,262-228,487) | 5.89 (4.73-6.03) | 1,310 (1,051-1,340) | 2.99x | 76% | 10% | 14% | 22.0% | `557-9-178-1263170-160` |

## World loop only (no brains)

| tier | world via Ruby API (updates/sec) | vs pure Ruby | kernel only, no Ruby glue (updates/sec) | crowd scan (ns/creature) | spread (API) |
|---|---:|---:|---:|---:|---:|
| pure Ruby interpreter | 137,687 (105,595-150,952) | 1.0x | n/a | n/a | 32.9% |
| pure Ruby + YJIT | 349,480 (295,199-362,839) | 2.5x | n/a | n/a | 19.4% |
| C + YJIT | 2,848,731 (2,292,262-3,058,315) | 20.7x | 3,246,770 (2,759,917-3,513,832) | 119.6 (111.1-135.5) | 26.9% |
| Rust + YJIT | 2,498,088 (2,325,292-2,622,953) | 18.1x | 2,890,079 (2,602,551-2,980,676) | n/a | 11.9% |
| asm + YJIT | 3,046,347 (2,796,636-3,131,988) | 22.1x | 3,496,816 (3,359,419-3,803,007) | 107.1 (99.9-111.1) | 11.0% |
| C, interpreter (extra) | 3,076,142 (2,673,095-3,156,316) | 22.3x | 3,506,024 (3,160,883-3,648,562) | 109.6 (106.9-120.4) | 15.7% |

## Correctness next to every timing

| check | distinct values across all 30 runs | ok |
|---|---|---|
| full-sim checksum (births-maxgen-alive-eaten-species) | `557-9-178-1263170-160` | yes |
| world-API benchmark: state digest after the first 600-tick block | `699cb7c5dfcb0295` | yes |
| kernel-only benchmark: state digest after the first 600-tick block | `699cb7c5dfcb0295` | yes |

Identical full-sim checksum across all 30 runs: **true** (`557-9-178-1263170-160`; births-maxgen-alive-food_eaten-species). The world backends are also bit-identical step by step (test/test_world_equivalence.rb).
