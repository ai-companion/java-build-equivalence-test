"""CLI entry point: python3 -m equivalence_test"""

from __future__ import annotations

import argparse
import json
import sys

from equivalence_test.core import run_comparison


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare rebuilt Java JARs against originals from Maven Central",
    )
    parser.add_argument(
        "--group", required=True,
        help="Maven group ID (e.g., org.springframework)",
    )
    parser.add_argument(
        "--modules", required=True, nargs="+",
        help="Maven artifact IDs (e.g., spring-core spring-beans)",
    )
    parser.add_argument(
        "--version", required=True,
        help="Maven version (e.g., 3.0.0.RELEASE)",
    )
    parser.add_argument(
        "--rebuilt-dir", required=True,
        help="Directory containing rebuilt JARs",
    )
    parser.add_argument(
        "--output", default=None,
        help="Path to write JSON report (default: stdout summary only)",
    )
    parser.add_argument(
        "--repo-url", default="https://repo1.maven.org/maven2",
        help="Maven repository URL (default: Maven Central)",
    )
    parser.add_argument(
        "--module-jar-map", default=None,
        help="JSON file mapping module names to rebuilt JAR filenames",
    )
    parser.add_argument(
        "--decompile", action="store_true", default=False,
        help="Enable Level 3 decompilation comparison (requires java on PATH)",
    )

    args = parser.parse_args()

    module_jar_map = None
    if args.module_jar_map:
        with open(args.module_jar_map) as f:
            module_jar_map = json.load(f)

    report = run_comparison(
        group=args.group,
        modules=args.modules,
        version=args.version,
        rebuilt_dir=args.rebuilt_dir,
        output_path=args.output,
        module_to_jar=module_jar_map,
        repo_url=args.repo_url,
    )

    print(report.summary())

    if args.output:
        print(f"\nJSON report written to: {args.output}")

    all_match = all(m.api_match for m in report.modules)
    return 0 if all_match else 1


if __name__ == "__main__":
    sys.exit(main())
