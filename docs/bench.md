# YARVPILLED benchmark

ruby 3.4.7 | x86_64-linux | 2000 ticks | seed 11 | 8 cpus

| tier | creatures/sec (think calls) | generations/sec | ticks/sec | speedup | world-loop micro (updates/sec) | allocations | GC runs | checksum |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| pure Ruby interpreter | 82100 | 2.17 | 481.4 | 1.0x | 152209 | 754993 | 81 | `557-9-178-1263170-160` |
| pure Ruby + YJIT | 153118 | 4.04 | 897.8 | 1.87x | 699381 | 758668 | 81 | `557-9-178-1263170-160` |
| C ext, interpreter (extra) | 227651 | 6.01 | 1334.8 | 2.77x | 13529984 | 752825 | 80 | `557-9-178-1263170-160` |
| C ext + YJIT | 288930 | 7.62 | 1694.1 | 3.52x | 15541226 | 756515 | 80 | `557-9-178-1263170-160` |

Identical checksum across tiers: **true** (births-maxgen-alive-food_eaten-species), i.e. every tier did exactly the same evolutionary work.
