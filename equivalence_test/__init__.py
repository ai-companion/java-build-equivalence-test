"""Java Build Equivalence Test — compare rebuilt JARs against originals from Maven Central."""

from equivalence_test.core import (
    compare_jars,
    compare_module,
    download_originals,
    run_comparison,
    EquivalenceReport,
    ModuleResult,
)

__all__ = [
    "compare_jars",
    "compare_module",
    "download_originals",
    "run_comparison",
    "EquivalenceReport",
    "ModuleResult",
]
