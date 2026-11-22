# YARVPILLED benchmark

ruby 3.4.7 | Intel(R) Xeon(R) Processor | 8 cpus | seed 11 | 2000 ticks | 5 runs per tier, each a fresh process | values are **median (min-max)**

## Full simulation (brains + world)

| tier | creatures/sec | generations/sec | ticks/sec | vs pure Ruby | time in brains (YARV think) | time compiling births (mutate+ISeq) | time in world (sense+act) | spread | checksum |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| pure Ruby interpreter | 79,543 (71,055-80,313) | 2.10 (1.87-2.12) | 466 (417-471) | 1.00x | 17% | 3% | 80% | 11.6% | `557-9-178-1263170-160` |
| pure Ruby + YJIT | 147,949 (139,349-155,673) | 3.90 (3.68-4.11) | 867 (817-913) | 1.86x | 31% | 6% | 63% | 11.0% | `557-9-178-1263170-160` |
| C + YJIT | 278,971 (265,787-303,899) | 7.36 (7.01-8.02) | 1,636 (1,558-1,782) | 3.51x | 72% | 13% | 15% | 13.7% | `557-9-178-1263170-160` |
| Rust + YJIT | 270,977 (254,027-287,471) | 7.15 (6.70-7.59) | 1,589 (1,489-1,686) | 3.41x | 70% | 12% | 17% | 12.3% | `557-9-178-1263170-160` |
| asm + YJIT | 275,521 (246,846-280,025) | 7.27 (6.51-7.39) | 1,616 (1,447-1,642) | 3.46x | 72% | 13% | 14% | 12.0% | `557-9-178-1263170-160` |
| C, interpreter (extra) | 215,625 (189,853-220,369) | 5.69 (5.01-5.81) | 1,264 (1,113-1,292) | 2.71x | 76% | 9% | 14% | 14.2% | `557-9-178-1263170-160` |

## World loop only (no brains)

| tier | world via Ruby API (updates/sec) | vs pure Ruby | kernel only, no Ruby glue (updates/sec) | crowd scan (ns/creature) | spread (API) |
|---|---:|---:|---:|---:|---:|
| pure Ruby interpreter | 145,500 (137,090-154,603) | 1.0x | n/a | n/a | 12.0% |
| pure Ruby + YJIT | 357,931 (354,188-371,538) | 2.5x | n/a | n/a | 4.8% |
| C + YJIT | 3,202,418 (2,860,074-3,352,682) | 22.0x | 3,792,146 (3,729,232-3,852,531) | 103.1 (99.4-106.7) | 15.4% |
| Rust + YJIT | 2,706,854 (2,654,423-2,776,398) | 18.6x | 3,089,648 (2,817,091-3,195,424) | n/a | 4.5% |
| asm + YJIT | 2,884,147 (2,787,973-3,074,170) | 19.8x | 3,509,464 (3,248,720-3,778,834) | 104.5 (101.5-111.9) | 9.9% |
| C, interpreter (extra) | 2,807,776 (2,487,747-3,035,365) | 19.3x | 3,584,645 (2,980,834-3,629,377) | 108.6 (107.7-157.3) | 19.5% |

Identical full-sim checksum across all 30 runs: **true** (`557-9-178-1263170-160`; births-maxgen-alive-food_eaten-species). The world backends are also bit-identical step by step (test/test_world_equivalence.rb).
