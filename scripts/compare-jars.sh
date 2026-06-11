#!/usr/bin/env bash
set -euo pipefail

# Java Build Equivalence Test — Shell Script
# Compares rebuilt JARs against originals from Maven Central.
# Requires: java, jar, javap, curl, diff

usage() {
    echo "Usage: $0 --group GROUP --version VERSION --rebuilt-dir DIR [--output FILE] MODULE..."
    echo ""
    echo "Example:"
    echo "  $0 --group org.springframework --version 3.0.0.RELEASE \\"
    echo "     --rebuilt-dir /path/to/jars spring-core spring-beans spring-context"
    echo ""
    echo "Options:"
    echo "  --group       Maven group ID (e.g., org.springframework)"
    echo "  --version     Maven version (e.g., 3.0.0.RELEASE)"
    echo "  --rebuilt-dir Directory containing rebuilt JARs"
    echo "  --output      Path to write report (default: stdout)"
    echo "  --repo-url    Maven repo URL (default: https://repo1.maven.org/maven2)"
    exit 1
}

GROUP=""
VERSION=""
REBUILT_DIR=""
OUTPUT=""
REPO_URL="https://repo1.maven.org/maven2"
MODULES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --group) GROUP="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --rebuilt-dir) REBUILT_DIR="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --repo-url) REPO_URL="$2"; shift 2 ;;
        --help|-h) usage ;;
        -*) echo "Unknown option: $1"; usage ;;
        *) MODULES+=("$1"); shift ;;
    esac
done

[ -z "$GROUP" ] || [ -z "$VERSION" ] || [ -z "$REBUILT_DIR" ] || [ ${#MODULES[@]} -eq 0 ] && usage

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/original" "$WORK_DIR/analysis"
GROUP_PATH=$(echo "$GROUP" | tr '.' '/')

REPORT="$WORK_DIR/report.txt"
TOTAL=0
INVENTORY_MATCH=0
API_MATCH=0
TOTAL_CLASSES=0

{
echo "============================================================"
echo "  Java Build Equivalence Report"
echo "  Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"
echo ""
echo "Original: $REPO_URL ($GROUP:*:$VERSION)"
echo "Rebuilt:  $REBUILT_DIR"
echo ""

for MODULE in "${MODULES[@]}"; do
    TOTAL=$((TOTAL + 1))
    JAR_NAME="${MODULE}-${VERSION}.jar"
    ORIG_JAR="$WORK_DIR/original/$JAR_NAME"
    REBUILT_JAR="$REBUILT_DIR/$JAR_NAME"

    echo "=== Comparing: $MODULE ==="

    # Download original
    ORIG_URL="$REPO_URL/$GROUP_PATH/$MODULE/$VERSION/$JAR_NAME"
    if ! curl -fsSL -o "$ORIG_JAR" "$ORIG_URL" 2>/dev/null; then
        echo "  ERROR: Failed to download $ORIG_URL"
        echo ""
        continue
    fi

    # Check rebuilt exists
    if [ ! -f "$REBUILT_JAR" ]; then
        echo "  ERROR: Rebuilt JAR not found: $REBUILT_JAR"
        echo ""
        continue
    fi

    # Size comparison
    ORIG_SIZE=$(stat -c%s "$ORIG_JAR" 2>/dev/null || stat -f%z "$ORIG_JAR")
    REBUILT_SIZE=$(stat -c%s "$REBUILT_JAR" 2>/dev/null || stat -f%z "$REBUILT_JAR")
    SIZE_DIFF=$((REBUILT_SIZE - ORIG_SIZE))
    if [ "$ORIG_SIZE" -gt 0 ]; then
        SIZE_PCT=$(echo "scale=1; $SIZE_DIFF * 100 / $ORIG_SIZE" | bc 2>/dev/null || echo "?")
    else
        SIZE_PCT="?"
    fi
    echo "  Size: original=$ORIG_SIZE rebuilt=$REBUILT_SIZE diff=$SIZE_DIFF (${SIZE_PCT}%)"

    # Class inventory
    jar tf "$ORIG_JAR" | grep '\.class$' | sort > "$WORK_DIR/analysis/orig-classes.txt"
    jar tf "$REBUILT_JAR" | grep '\.class$' | sort > "$WORK_DIR/analysis/rebuilt-classes.txt"

    ORIG_COUNT=$(wc -l < "$WORK_DIR/analysis/orig-classes.txt")
    REBUILT_COUNT=$(wc -l < "$WORK_DIR/analysis/rebuilt-classes.txt")
    COMMON=$(comm -12 "$WORK_DIR/analysis/orig-classes.txt" "$WORK_DIR/analysis/rebuilt-classes.txt" | wc -l)
    TOTAL_CLASSES=$((TOTAL_CLASSES + ORIG_COUNT))

    echo "  Classes: original=$ORIG_COUNT rebuilt=$REBUILT_COUNT common=$COMMON"

    MISSING=$(comm -23 "$WORK_DIR/analysis/orig-classes.txt" "$WORK_DIR/analysis/rebuilt-classes.txt")
    EXTRA=$(comm -13 "$WORK_DIR/analysis/orig-classes.txt" "$WORK_DIR/analysis/rebuilt-classes.txt")

    if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then
        echo "  Class inventory: MATCH"
        INVENTORY_MATCH=$((INVENTORY_MATCH + 1))
    else
        echo "  Class inventory: DIFFERS"
        [ -n "$MISSING" ] && echo "    Missing: $(echo "$MISSING" | wc -l) classes"
        [ -n "$EXTRA" ] && echo "    Extra: $(echo "$EXTRA" | wc -l) classes"
    fi

    # Public API comparison
    echo "  Comparing public API signatures..."
    API_DIFFS=0
    API_DIFF_DETAILS=""

    while IFS= read -r cls_file; do
        cls_name=$(echo "$cls_file" | sed 's/\.class$//' | tr '/' '.')
        orig_api=$(javap -public -classpath "$ORIG_JAR" "$cls_name" 2>/dev/null || true)
        rebuilt_api=$(javap -public -classpath "$REBUILT_JAR" "$cls_name" 2>/dev/null || true)
        if [ "$orig_api" != "$rebuilt_api" ]; then
            API_DIFFS=$((API_DIFFS + 1))
            diff_output=$(diff <(echo "$orig_api") <(echo "$rebuilt_api") 2>/dev/null || true)
            API_DIFF_DETAILS="${API_DIFF_DETAILS}    ${cls_name}:\n$(echo "$diff_output" | head -5 | sed 's/^/      /')\n"
        fi
    done < <(comm -12 "$WORK_DIR/analysis/orig-classes.txt" "$WORK_DIR/analysis/rebuilt-classes.txt")

    if [ "$API_DIFFS" -eq 0 ]; then
        echo "  Public API: MATCH (all $COMMON classes identical)"
        API_MATCH=$((API_MATCH + 1))
    else
        echo "  Public API: $API_DIFFS classes differ"
        echo -e "$API_DIFF_DETAILS"
    fi

    echo ""
done

echo "============================================================"
echo "  SUMMARY"
echo "============================================================"
echo ""
echo "  Modules total:          $TOTAL"
echo "  Modules compared:       $TOTAL"
echo "  Class inventory match:  $INVENTORY_MATCH / $TOTAL"
echo "  Public API match:       $API_MATCH / $TOTAL"
echo "  Total classes:          $TOTAL_CLASSES"

if [ "$API_MATCH" -eq "$TOTAL" ]; then
    echo ""
    echo "  RESULT: All modules are API-equivalent."
else
    echo ""
    echo "  RESULT: Some modules have API differences. See details above."
fi
} | tee "${OUTPUT:-/dev/null}"

[ -z "$OUTPUT" ] || echo "Report written to: $OUTPUT"

[ "$API_MATCH" -eq "$TOTAL" ] && exit 0 || exit 1
