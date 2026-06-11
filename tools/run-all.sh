#!/usr/bin/env bash
set -euo pipefail

# Java Build Equivalence Test Bed — Fast Version
# Runs comparison tools against original vs rebuilt JARs
#
# Usage: ./run-all.sh <group> <version> <rebuilt-dir> <module1> [module2 ...]

GROUP="$1"; shift
VERSION="$1"; shift
REBUILT_DIR="$1"; shift
MODULES=("$@")

GROUP_PATH=$(echo "$GROUP" | tr '.' '/')
RESULTS_DIR="${RESULTS_DIR:-/workspace/results}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$RESULTS_DIR" "$WORK_DIR/original"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
REPORT="$RESULTS_DIR/equivalence-report.txt"

{
echo "============================================================"
echo "  Java Build Equivalence Test Bed"
echo "  $TIMESTAMP"
echo "============================================================"
echo "  Group:   $GROUP"
echo "  Version: $VERSION"
echo "  Rebuilt: $REBUILT_DIR"
echo "  Modules: ${MODULES[*]}"
echo "============================================================"
echo ""

# Download originals from Maven Central
echo ">>> Downloading originals from Maven Central"
for MODULE in "${MODULES[@]}"; do
    JAR_NAME="${MODULE}-${VERSION}.jar"
    URL="https://repo1.maven.org/maven2/$GROUP_PATH/$MODULE/$VERSION/$JAR_NAME"
    if curl -fsSL -o "$WORK_DIR/original/$JAR_NAME" "$URL" 2>/dev/null; then
        echo "  $MODULE: $(stat -c%s "$WORK_DIR/original/$JAR_NAME") bytes"
    else
        echo "  $MODULE: FAILED to download"
    fi
done
echo ""

TOTAL=${#MODULES[@]}

# ═══════════════════════════════════════════════════════════════
# TOOL 1: japicmp — Binary/Source API Compatibility
# ═══════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOOL 1: japicmp  (binary + source compatibility)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mkdir -p "$RESULTS_DIR/japicmp"
JAPICMP_COMPAT=0

for MODULE in "${MODULES[@]}"; do
    JAR_NAME="${MODULE}-${VERSION}.jar"
    ORIG="$WORK_DIR/original/$JAR_NAME"
    REBUILT="$REBUILT_DIR/$JAR_NAME"
    [ -f "$ORIG" ] && [ -f "$REBUILT" ] || { echo "  $MODULE: SKIP"; continue; }

    OUTPUT_FILE="$RESULTS_DIR/japicmp/${MODULE}.txt"
    java -jar /workspace/tools/japicmp.jar \
        --old "$ORIG" --new "$REBUILT" \
        --ignore-missing-classes \
        --no-annotations \
        > "$OUTPUT_FILE" 2>&1 || true

    # Parse results — use tr to strip newlines from grep -c output
    UNCHANGED=$(grep -c "UNCHANGED" "$OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]')
    UNCHANGED=${UNCHANGED:-0}
    MODIFIED=$(grep -c "MODIFIED\|REMOVED\|===  NEW" "$OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]')
    MODIFIED=${MODIFIED:-0}
    BINARY_INCOMPAT=$(grep -c "BINARY_INCOMPATIBLE" "$OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]')
    BINARY_INCOMPAT=${BINARY_INCOMPAT:-0}
    SOURCE_INCOMPAT=$(grep -c "SOURCE_INCOMPATIBLE" "$OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]')
    SOURCE_INCOMPAT=${SOURCE_INCOMPAT:-0}

    if [ "$BINARY_INCOMPAT" -eq 0 ] && [ "$SOURCE_INCOMPAT" -eq 0 ]; then
        echo "  $MODULE: COMPATIBLE ($UNCHANGED unchanged, $MODIFIED annotations)"
        JAPICMP_COMPAT=$((JAPICMP_COMPAT + 1))
    else
        echo "  $MODULE: INCOMPATIBLE (binary=$BINARY_INCOMPAT source=$SOURCE_INCOMPAT)"
        grep "BINARY_INCOMPATIBLE\|SOURCE_INCOMPATIBLE" "$OUTPUT_FILE" | head -5 | sed 's/^/    /'
    fi
done
echo "  RESULT: $JAPICMP_COMPAT/$TOTAL modules binary-compatible"
echo ""

# ═══════════════════════════════════════════════════════════════
# TOOL 2: Class Inventory — File-level JAR comparison
# ═══════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOOL 2: Class Inventory  (jar tf comparison)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
INVENTORY_MATCH=0

for MODULE in "${MODULES[@]}"; do
    JAR_NAME="${MODULE}-${VERSION}.jar"
    ORIG="$WORK_DIR/original/$JAR_NAME"
    REBUILT="$REBUILT_DIR/$JAR_NAME"
    [ -f "$ORIG" ] && [ -f "$REBUILT" ] || { echo "  $MODULE: SKIP"; continue; }

    jar tf "$ORIG" | grep '\.class$' | sort > "$WORK_DIR/orig-cls.txt"
    jar tf "$REBUILT" | grep '\.class$' | sort > "$WORK_DIR/rebuilt-cls.txt"
    ORIG_COUNT=$(wc -l < "$WORK_DIR/orig-cls.txt")
    MISSING=$(comm -23 "$WORK_DIR/orig-cls.txt" "$WORK_DIR/rebuilt-cls.txt" | wc -l)
    EXTRA=$(comm -13 "$WORK_DIR/orig-cls.txt" "$WORK_DIR/rebuilt-cls.txt" | wc -l)

    if [ "$MISSING" -eq 0 ] && [ "$EXTRA" -eq 0 ]; then
        echo "  $MODULE: MATCH ($ORIG_COUNT classes)"
        INVENTORY_MATCH=$((INVENTORY_MATCH + 1))
    else
        echo "  $MODULE: DIFFERS (-$MISSING +$EXTRA from $ORIG_COUNT original)"
    fi
done
echo "  RESULT: $INVENTORY_MATCH/$TOTAL modules class-inventory identical"
echo ""

# ═══════════════════════════════════════════════════════════════
# TOOL 3: SHA-256 — Byte-level class file hashing
# ═══════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOOL 3: SHA-256  (byte-level .class file hashing)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mkdir -p "$RESULTS_DIR/sha256"
SHA_IDENTICAL=0
TOTAL_CLASSES=0
TOTAL_CLASS_MATCH=0

for MODULE in "${MODULES[@]}"; do
    JAR_NAME="${MODULE}-${VERSION}.jar"
    ORIG="$WORK_DIR/original/$JAR_NAME"
    REBUILT="$REBUILT_DIR/$JAR_NAME"
    [ -f "$ORIG" ] && [ -f "$REBUILT" ] || { echo "  $MODULE: SKIP"; continue; }

    rm -rf "$WORK_DIR/sha-orig" "$WORK_DIR/sha-rebuilt"
    mkdir -p "$WORK_DIR/sha-orig" "$WORK_DIR/sha-rebuilt"
    (cd "$WORK_DIR/sha-orig" && jar xf "$ORIG")
    (cd "$WORK_DIR/sha-rebuilt" && jar xf "$REBUILT")

    MOD_TOTAL=0
    MOD_MATCH=0
    MOD_DIFF=0

    while IFS= read -r rel; do
        MOD_TOTAL=$((MOD_TOTAL + 1))
        ORIG_SHA=$(sha256sum "$WORK_DIR/sha-orig/$rel" | cut -d' ' -f1)
        REBUILT_F="$WORK_DIR/sha-rebuilt/$rel"
        if [ -f "$REBUILT_F" ]; then
            REBUILT_SHA=$(sha256sum "$REBUILT_F" | cut -d' ' -f1)
            if [ "$ORIG_SHA" = "$REBUILT_SHA" ]; then
                MOD_MATCH=$((MOD_MATCH + 1))
            else
                MOD_DIFF=$((MOD_DIFF + 1))
            fi
        else
            MOD_DIFF=$((MOD_DIFF + 1))
        fi
    done < <(cd "$WORK_DIR/sha-orig" && find . -name "*.class" | sed 's|^\./||' | sort)

    TOTAL_CLASSES=$((TOTAL_CLASSES + MOD_TOTAL))
    TOTAL_CLASS_MATCH=$((TOTAL_CLASS_MATCH + MOD_MATCH))

    if [ "$MOD_DIFF" -eq 0 ]; then
        echo "  $MODULE: IDENTICAL ($MOD_MATCH/$MOD_TOTAL classes byte-identical)"
        SHA_IDENTICAL=$((SHA_IDENTICAL + 1))
    else
        PCT=$((MOD_MATCH * 100 / MOD_TOTAL))
        echo "  $MODULE: $MOD_MATCH/$MOD_TOTAL identical (${PCT}%), $MOD_DIFF differ"
    fi
done
echo "  RESULT: $SHA_IDENTICAL/$TOTAL modules byte-identical, $TOTAL_CLASS_MATCH/$TOTAL_CLASSES classes overall"
echo ""

# ═══════════════════════════════════════════════════════════════
# TOOL 4: Manifest & Metadata Comparison
# ═══════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOOL 4: Manifest & Metadata"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
mkdir -p "$RESULTS_DIR/metadata"
MANIFEST_MATCH=0

for MODULE in "${MODULES[@]}"; do
    JAR_NAME="${MODULE}-${VERSION}.jar"
    ORIG="$WORK_DIR/original/$JAR_NAME"
    REBUILT="$REBUILT_DIR/$JAR_NAME"
    [ -f "$ORIG" ] && [ -f "$REBUILT" ] || { echo "  $MODULE: SKIP"; continue; }

    ORIG_SIZE=$(stat -c%s "$ORIG")
    REBUILT_SIZE=$(stat -c%s "$REBUILT")
    SIZE_DIFF=$((REBUILT_SIZE - ORIG_SIZE))
    PCT=$(echo "scale=1; $SIZE_DIFF * 100 / $ORIG_SIZE" | bc 2>/dev/null || echo "?")

    unzip -p "$ORIG" META-INF/MANIFEST.MF > "$WORK_DIR/m1.txt" 2>/dev/null || true
    unzip -p "$REBUILT" META-INF/MANIFEST.MF > "$WORK_DIR/m2.txt" 2>/dev/null || true
    MANIFEST_LINES=$(diff "$WORK_DIR/m1.txt" "$WORK_DIR/m2.txt" 2>/dev/null | grep -c "^[<>]" || echo 0)
    diff "$WORK_DIR/m1.txt" "$WORK_DIR/m2.txt" > "$RESULTS_DIR/metadata/${MODULE}-manifest.diff" 2>/dev/null || true

    if [ "$MANIFEST_LINES" -eq 0 ]; then
        echo "  $MODULE: MANIFEST IDENTICAL, size ${PCT}%"
        MANIFEST_MATCH=$((MANIFEST_MATCH + 1))
    else
        echo "  $MODULE: MANIFEST DIFFERS ($MANIFEST_LINES lines), size ${PCT}%"
    fi
done
echo "  RESULT: $MANIFEST_MATCH/$TOTAL manifests identical"
echo ""

# ═══════════════════════════════════════════════════════════════
# TOOL 5: Whole-JAR SHA-256
# ═══════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TOOL 5: Whole-JAR SHA-256"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
JAR_MATCH=0

for MODULE in "${MODULES[@]}"; do
    JAR_NAME="${MODULE}-${VERSION}.jar"
    ORIG="$WORK_DIR/original/$JAR_NAME"
    REBUILT="$REBUILT_DIR/$JAR_NAME"
    [ -f "$ORIG" ] && [ -f "$REBUILT" ] || { echo "  $MODULE: SKIP"; continue; }

    ORIG_SHA=$(sha256sum "$ORIG" | cut -d' ' -f1)
    REBUILT_SHA=$(sha256sum "$REBUILT" | cut -d' ' -f1)

    if [ "$ORIG_SHA" = "$REBUILT_SHA" ]; then
        echo "  $MODULE: IDENTICAL"
        JAR_MATCH=$((JAR_MATCH + 1))
    else
        echo "  $MODULE: DIFFERS"
        echo "    original: $ORIG_SHA"
        echo "    rebuilt:  $REBUILT_SHA"
    fi
done
echo "  RESULT: $JAR_MATCH/$TOTAL JARs byte-identical"
echo ""

# ═══════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════
echo "============================================================"
echo "  FINAL SUMMARY — $GROUP $VERSION"
echo "============================================================"
echo ""
echo "  Tool 1 (japicmp):        $JAPICMP_COMPAT/$TOTAL binary-compatible"
echo "  Tool 2 (class inventory): $INVENTORY_MATCH/$TOTAL class sets identical"
echo "  Tool 3 (SHA-256 classes): $SHA_IDENTICAL/$TOTAL fully byte-identical ($TOTAL_CLASS_MATCH/$TOTAL_CLASSES classes)"
echo "  Tool 4 (manifests):       $MANIFEST_MATCH/$TOTAL manifests identical"
echo "  Tool 5 (whole JAR hash):  $JAR_MATCH/$TOTAL JARs byte-identical"
echo ""
echo "  Interpretation:"
echo "    japicmp COMPATIBLE     = safe binary drop-in replacement"
echo "    Class inventory MATCH  = same .class files in both JARs"
echo "    SHA-256 classes MATCH  = bytecode is bit-for-bit identical"
echo "    Manifest MATCH         = JAR metadata identical"
echo "    Whole JAR MATCH        = fully reproducible build"
echo ""
echo "============================================================"

} 2>&1 | tee "$REPORT"

echo ""
echo "Full report: $REPORT"
echo "Tool outputs: $RESULTS_DIR/"
