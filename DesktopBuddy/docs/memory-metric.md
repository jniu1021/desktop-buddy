# Memory metric contract

Desktop Buddy's displayed memory percentage is the §6 **non-cache physical-memory
occupancy** metric. It is not presented as a byte-for-byte copy of Activity Monitor's
`Memory Used` value.

## Implemented formula

The macOS sensor reads `vm_statistics64` through the public `host_statistics64` API and
computes:

```text
adjusted free pages = max(free_count - speculative_count, 0)
reclaimable pages = adjusted free pages + purgeable_count + external_page_count
used bytes = max(physical memory - reclaimable pages × page size, 0)
usage percent = used bytes / physical memory
```

The 70% and 85% presentation thresholds apply to this metric. Compression, swap-out
rate, swap occupancy, and system memory pressure remain separate diagnostic context and
do not replace this percentage.

## Known Activity Monitor divergence

Apple publicly describes `Memory Used`, `Cached Files`, and memory pressure, and exposes
the individual `vm_statistics64` counters. Apple does not publish Activity Monitor's
exact `Memory Used` calculation as a supported API contract.

Desktop Buddy currently treats every `external_page_count` page as reclaimable
file-backed cache. That matches the product goal of excluding readily reclaimable file
cache, but it can understate occupancy when external pages belong to actively mapped
executables or files. Activity Monitor may classify some of those pages differently, so
the two percentages can diverge even when sampled at the same instant.

This is an intentional, documented limitation for the private alpha. We do not scrape
Activity Monitor's UI or request Accessibility/Screen Recording permission to manufacture
a fragile parity test. Validation should compare trends and threshold behavior, not exact
byte equality.

References:

- [Apple: View memory usage in Activity Monitor](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac)
- [Apple: `vm_statistics64_data_t`](https://developer.apple.com/documentation/kernel/vm_statistics64_data_t)
