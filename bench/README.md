# sill bench

`sill bench --suite=v1` is the release contract (PRD §12 + Appendix A): no stable
tag without a Workspace-shape bench table in CI.

Suite `v1` cases:

| Case                | Budget                                              |
|---------------------|-----------------------------------------------------|
| `key_to_photon`     | P50 ≤ 5ms @120Hz Raw (requires libghostty backend)  |
| `cat_ascii_150mb`   | same order as Ghostty nightly, Workspace open       |
| `idle_cpu`          | ≤ 2% after 5s, 1 surface + rail + idle composer     |
| `idle_rss`          | macOS ≤ 90MB / Linux ≤ 120MB                        |
| `occluded_rss`      | 8 panes, 7 occluded — no 8× visible RAM             |

Release notes must list CPU / GPU / OS / Ghostty comparison version / 120×40 cell.
Cases needing the real libghostty backend report `skipped (needs libghostty)`
until `vendor/libghostty` lands; they may never be reported from Terminal Mode.
