# Java Build Equivalence Test

Tools for verifying that rebuilt Java artifacts are semantically equivalent to their original published versions.

## The Problem

When you rebuild a historical Java project from source (e.g., for CVE backporting), the output JARs may not be byte-identical to the originals — but they should be **functionally equivalent**. You need a way to verify this.

Differences can arise from:
- Different compiler (Sun javac vs Eclipse JDT vs OpenJDK javac)
- Different JDK vendor/version (Sun vs Zulu vs Temurin)
- Different dependency versions on the compilation classpath
- Missing build steps (e.g., OSGi manifest generation)
- Different build tool versions

This tool compares rebuilt JARs against the originals (downloaded from Maven Central) and reports exactly what matches and what differs.

## What It Checks

### Level 1: Class Inventory
Lists every `.class` file in both JARs and diffs them. Catches missing or extra classes.

### Level 2: Public API Surface
Uses `javap -public` to compare every public method signature, field declaration, constructor, and class hierarchy. Catches changed APIs. This does NOT require matching the original compiler or JDK — `javap` reads the standardized class file format (JVM Spec §4).

### Level 3: Bytecode Decompilation (optional)
Uses CFR decompiler to reconstruct Java source from bytecode and compares method implementations. Catches behavioral differences inside methods. Includes noise filtering for compiler artifacts (variable names, constant pool ordering, synthetic methods).

## Quick Start

### CLI

```bash
# Compare rebuilt JARs against Maven Central originals
python3 -m equivalence_test \
    --group org.springframework \
    --modules spring-core spring-beans spring-context \
    --version 3.0.0.RELEASE \
    --rebuilt-dir /path/to/rebuilt/jars

# With JSON report output
python3 -m equivalence_test \
    --group org.springframework \
    --modules spring-core spring-beans \
    --version 3.0.0.RELEASE \
    --rebuilt-dir /path/to/jars \
    --output report.json

# With Level 3 decompilation (requires java on PATH)
python3 -m equivalence_test \
    --group org.springframework \
    --modules spring-core \
    --version 3.0.0.RELEASE \
    --rebuilt-dir /path/to/jars \
    --decompile
```

### Python API

```python
from equivalence_test import run_comparison

report = run_comparison(
    group="org.springframework",
    modules=["spring-core", "spring-beans", "spring-context"],
    version="3.0.0.RELEASE",
    rebuilt_dir="/path/to/rebuilt/jars",
    output_path="report.json",
)

print(report.summary())
# Equivalence Report
# ============================================================
# Modules compared:      3
# Class inventory match: 3 / 3
# Public API match:      3 / 3
# Total classes:         1362
```

### Shell Script (standalone, no Python needed)

```bash
# Requires: java, jar, javap, curl, diff
./compare-jars.sh \
    --group org.springframework \
    --version 3.0.0.RELEASE \
    --rebuilt-dir /path/to/jars \
    spring-core spring-beans spring-context
```

## Requirements

- Python 3.6+ (for the Python tool)
- `java`, `jar`, `javap` on PATH (any JDK version — doesn't need to match the build)
- `curl` (for downloading originals from Maven Central)
- `diff` (standard Unix)
- Optional: CFR decompiler JAR (auto-downloaded for Level 3)

## Proven Results

Tested on Spring Framework v3.0.0.RELEASE (December 2009, rebuilt in 2026):

| Metric | Result |
|--------|--------|
| Modules compared | 15 / 15 |
| Total classes | 3,846 |
| Class inventory match | 15 / 15 (100%) |
| Public API match | 14 / 15 (99.3%) |

The single API "difference" was in spring-aspects: two AspectJ compiler-generated synthetic method names (`ajc$if_0` vs `ajc$if$6f1`) — internal compiler artifacts, not callable by user code.

## What Each Level Can and Cannot Verify

| What could differ | Level 1 | Level 2 | Level 3 |
|---|---|---|---|
| Missing/extra class files | Catches | Catches | Catches |
| Changed method signature | - | Catches | Catches |
| Changed return type | - | Catches | Catches |
| Changed class hierarchy | - | Catches | Catches |
| Different method implementation | - | - | Catches |
| Different dependency behavior at runtime | - | - | - |
| Reflection/dynamic dispatch differences | - | - | - |

## Documentation

- [Equivalence Testing — Concepts and Limitations](docs/equivalence-testing.md)
- [Build Root Methodology — How to Rebuild Ancient Packages](docs/build-root-methodology.md)

## License

MIT
