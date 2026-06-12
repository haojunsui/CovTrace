[![Xcode - Build and Analyze](https://github.com/haojunsui/CovTrace/actions/workflows/xcode-build-all.yml/badge.svg)](https://github.com/haojunsui/CovTrace/actions/workflows/xcode-build-all.yml)

# CovTrace

**CovTrace turns real app execution into linker order files — so your iOS/macOS app launches faster.**

CovTrace is a toolchain for **order file generation**: it records the exact functions your binary executes (typically during startup), resolves them to symbols, and emits a Clang/LLVM **`.order` file** you can feed straight back into the linker. By packing the functions that run at launch into adjacent virtual-memory pages, the linker dramatically reduces the number of page faults during startup — one of the most effective, lowest-risk app-launch optimizations available.

CovTrace also ships an **Order File Analyzer** that quantifies the win *before* you ship: it tells you how many page faults an order file will save and estimates the startup time you'll gain.

---

## Why order files matter

When an app launches, the kernel pages in the `__TEXT` section of your binary on demand. If the functions executed at startup are scattered across many virtual-memory pages, each one triggers a separate page fault. An **order file** instructs the linker to lay those functions out contiguously, so the same startup work touches far fewer pages.

```
Without order file:           With order file:
┌────┬────┬────┬────┐         ┌────┬────┬────┬────┐
│ f1 │    │ f3 │    │         │ f1 │ f2 │ f3 │ f4 │  ← startup functions packed together
├────┼────┼────┼────┤         ├────┼────┼────┼────┤
│    │ f2 │    │ f4 │         │ ...│ ...│ ...│ ...│  ← everything else
└────┴────┴────┴────┘         └────┴────┴────┴────┘
 4 page faults on launch       1 page fault on launch
```

CovTrace generates that order file from *actual* runtime behavior, not guesswork.

---

## How it works

CovTrace is a three-stage pipeline plus an analyzer:

```
  ┌─────────────────────┐   ~/Library/csan.txt    ┌──────────────────┐   <module>.order   ┌────────────────────┐
  │  CoverageSanitizer  │ ──────────────────────► │   Symbolicator   │ ─────────────────► │   (link the app)   │
  │  (runs in your app) │   raw addresses +       │  csansymbolicator│   ordered mangled  │  -order_file ...   │
  └─────────────────────┘   loaded module info    └──────────────────┘   symbol names     └────────────────────┘
                                                            │
                                                            │  <module>.order  +  Xcode LinkMap
                                                            ▼
                                                   ┌────────────────────┐
                                                   │  OrderFileAnalyzer │  →  page faults saved,
                                                   │  orderfileanalyzer │     estimated time saved
                                                   └────────────────────┘
```

| Component | Role |
|-----------|------|
| **CoverageSanitizer** | A tiny C library linked into your app. Using Clang's coverage instrumentation (`-fsanitize-coverage=trace-pc-guard`), it records the return address of every executed function — in execution order — to `~/Library/csan.txt`, along with the load addresses of each module. |
| **Symbolicator** (`csansymbolicator`) | Resolves the recorded addresses back to mangled symbol names using Apple's CoreSymbolication framework, and writes one `.order` file per module — the file the linker consumes. |
| **OrderFileAnalyzer** (`orderfileanalyzer`) | Compares an order file against the app's Xcode LinkMap and reports how many VM page faults the ordering eliminates and the estimated startup time saved. |
| **Example** | A minimal iOS/macOS app demonstrating how to integrate the sanitizer and produce an order file. |

---

## Order file generation — end to end

### 1. Instrument and run your app

Link the **CoverageSanitizer** library (`libCovTrace.a`) into your app and build with Clang coverage instrumentation enabled:

```
-fsanitize-coverage=trace-pc-guard
```

Run the app through the scenario you want to optimize — usually **cold launch up to first meaningful screen**. As it runs, the sanitizer streams executed function addresses and loaded-module info to:

```
~/Library/csan.txt
```

Each line is either an executed return address or a loaded module record:

```
0x1023ab8c4
0x1023ab9c4
0x1022e8000 - 0x10cc8ffff: /path/to/Example.app/Example (36601856)
```

### 2. Symbolicate into a `.order` file

Turn the raw trace into ordered, linker-ready symbol names:

```bash
csansymbolicator -i ~/Library/csan.txt -o ./orderfiles [-a /path/to/Example.app]
```

| Flag | Description |
|------|-------------|
| `-i <input>`  | Coverage trace produced by the sanitizer (e.g. `~/Library/csan.txt`). |
| `-o <output>` | Output directory; one `<module>.order` file is written per module. |
| `-a <appPath>` | *(Optional, iOS)* Path to the app bundle. Needed because on-device the binary loads from `/private/var/containers/Bundle/Application/...`, which isn't where the symbols live. |

The resulting `<module>.order` contains mangled symbol names, one per line, in execution order:

```
_ZN12MyNamespace8MyClassC2Ev
_ZN12MyNamespace13InitMethodEv
_ZN12MyNamespace9MainLoopEv
```

### 3. Analyze the expected win

Before linking with the new order file, measure its impact against the app's **Xcode LinkMap** (enable *Write Link Map File* in your build settings):

```bash
orderfileanalyzer ./orderfiles/Example.order \
  /path/to/Example-LinkMap-normal-arm64.txt
```

Example report:

```
Linkmaps __TEXT summary:
    Begin address: 0x...
    Assigned size: ... MB
    Total symbols count: ...
    Duplicate symbols size: ... KB
    # of address jumped symbols: ...
    # of VM pages assigned: ...

Order file summary:
    # of ordered symbols: ...
    # of non-applicable symbols: ...
    # of VM pages faults on startup before ordering: ...
    # of VM pages faults on startup after ordering: ...
    # of page faults saved: ...
    Estimated time saved: ... ms
```

**How the estimate is computed:**

- **Before ordering:** count the *distinct* VM pages the startup symbols are scattered across in the current layout.
- **After ordering:** `ceil(total size of ordered symbols / page size)` — the minimum pages they'd occupy if packed contiguously.
- **Page faults saved** = pages before − pages after.
- **Estimated time saved** = page faults saved × `0.5 ms` (a conservative per-fault cost for SSD-backed storage).

Page size is inferred from the LinkMap path: **16 KB** for iOS / Apple-silicon macOS, **4 KB** for Intel macOS.

The analyzer also flags **duplicate symbols** and **address-jumped symbols**, which indicate layout issues worth cleaning up.

### 4. Link with the order file

Feed the generated `.order` file to the linker (Xcode build setting **Order File** / `ORDER_FILE`, or `-order_file <path>`), then rebuild. Re-run the analyzer on the new LinkMap to confirm the gains landed.

---

## Helper scripts

Located in [`CovTrace/CovTrace/script/`](CovTrace/CovTrace/script/):

| Script | Purpose |
|--------|---------|
| `mergeOrderFile.py` | Consolidates multiple `.order` files (e.g. from several runs or modules) into a merged set under `<dir>/Merged/`. Run: `python3 mergeOrderFile.py <dir>` |
| `injectOrderFile.sh` | Splices one order file into another after a given anchor symbol (falling back to appending), stripping comment lines. |
| `copy_core_symbolication_framework.sh` | Build phase that copies `CoreSymbolicationDT.framework` from your Xcode installation into the built products. |

---

## Building

CovTrace is built with **Xcode**. Open the workspace:

```bash
open CovTrace.xcworkspace
```

Targets include `libCovTrace.a` (the coverage sanitizer, written in plain C to avoid Objective-C runtime dependencies) and the `csansymbolicator` command-line tool. The Symbolicator and OrderFileAnalyzer are written in Objective-C.

### Requirements

- **Xcode** with the (Apple-internal) `CoreSymbolicationDT.framework` — copied automatically via the build script above.
- **Clang** with `trace-pc-guard` coverage support.
- **Python 3** (for `mergeOrderFile.py`).
- iOS SDK / macOS SDK as appropriate for your target.

---

## Repository layout

```
CovTrace/
├── CovTrace/CovTrace/
│   ├── CoverageSanitizer/    # C library: records executed addresses → ~/Library/csan.txt
│   ├── Symbolicator/         # csansymbolicator: addresses → <module>.order
│   ├── OrderFileAnalyzer/    # orderfileanalyzer: order file + LinkMap → page-fault analysis
│   └── script/               # merge / inject / framework-copy helpers
├── Example/                  # Sample iOS/macOS app for integration & testing
├── CovTrace.xcworkspace/
└── LICENSE
```

---

## License

MIT License © 2026 Haojun Sui. See [LICENSE](LICENSE).
