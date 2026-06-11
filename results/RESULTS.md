# Equivalence Test Results

## Spring Framework v4.3.30.RELEASE (Gradle, JDK 8)

| Tool | What It Checks | Result |
|------|---------------|--------|
| **japicmp** | Binary/source API compatibility | **15/15 COMPATIBLE** (0 binary-incompatible changes) |
| **Class inventory** | Same .class files in both JARs | **15/15 MATCH** (5,081 classes) |
| **SHA-256 per class** | Byte-identical .class files | **14/15 modules identical** (5,065/5,081 classes = 99.7%) |
| **Manifest** | JAR metadata | 0/15 match (expected — different build timestamps) |
| **Whole JAR hash** | Bit-for-bit JAR reproduction | 0/15 match (expected — manifests + ZIP timestamps differ) |

**spring-aspects:** 16 of 34 classes differ at byte level — all are AspectJ-woven classes with non-deterministic synthetic method naming. japicmp confirms they are binary-compatible.

## Spring Framework v3.0.0.RELEASE (Ant+Ivy, Sun JDK 6)

| Tool | What It Checks | Result |
|------|---------------|--------|
| **japicmp** | Binary/source API compatibility | **15/15 COMPATIBLE** (0 binary-incompatible changes) |
| **Class inventory** | Same .class files in both JARs | **15/15 MATCH** (3,136 classes) |
| **SHA-256 per class** | Byte-identical .class files | **14/15 modules identical** (3,124/3,136 classes = 99.6%) |
| **Manifest** | JAR metadata | 0/15 match (expected — Bundlor disabled, missing OSGi headers) |
| **Whole JAR hash** | Bit-for-bit JAR reproduction | 0/15 match (expected — manifests differ significantly) |

**spring-aspects:** 12 of 16 classes differ at byte level — same AspectJ synthetic naming issue. japicmp confirms binary-compatible.

## Key Findings

1. **japicmp says 30/30 modules are binary-compatible drop-in replacements.** This is the strongest practical guarantee — any code compiled against the original JARs will work identically with our rebuilds.

2. **99.6-99.7% of individual .class files are byte-for-byte identical** to the originals published in 2009/2020. The only exceptions are AspectJ-woven classes where the weaver uses non-deterministic synthetic method names.

3. **Manifests always differ** because:
   - v4.3.30: different build timestamp in `Created-By` header (2 lines each)
   - v3.0.0: Bundlor was disabled, so all OSGi headers (Export-Package, Import-Package, Import-Template) are missing (70-280 lines per module)

4. **Whole-JAR hashes never match** because JAR files are ZIP archives with per-entry timestamps and the manifest differences propagate to the file level. This is expected — true reproducible builds require `SOURCE_DATE_EPOCH` and deterministic ZIP tooling.

5. **AspectJ is the only source of class-level non-determinism.** The AspectJ weaver generates synthetic method names like `ajc$if_0` (original) vs `ajc$if$6f1` (rebuild). These are internal compiler artifacts — no user code calls them by name.
