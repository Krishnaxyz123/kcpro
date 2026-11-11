#!/usr/bin/env python3
"""
Phase 1 Advanced RAG Regression Testing Script

Tests all Phase 1 features:
- Contextual retrieval (semantic search)
- Query decomposition (filter extraction)
- Enhanced LLM context (structured metadata)
- Hybrid search (vector + keyword)
- Phone prefix search (wildcard matching)

Usage:
    python test_phase1_regression.py
    python test_phase1_regression.py --verbose
    python test_phase1_regression.py --query "food banks in Lafayette"
"""

import argparse
import sys
import time
from dataclasses import dataclass
from typing import Dict, List, Optional

import httpx
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

console = Console()


@dataclass
class TestCase:
    """Test case for Phase 1 features."""

    name: str
    query: str
    feature_tested: str
    expected_keywords: List[str]  # Keywords that should appear in results
    expected_min_sources: int = 1  # Minimum number of sources expected
    expected_metadata: Optional[List[str]] = None  # Metadata fields that should be present


# Phase 1 Test Cases
TEST_CASES = [
    TestCase(
        name="Basic search with structured metadata",
        query="food banks in Lafayette",
        feature_tested="Structured Metadata Display",
        expected_keywords=["Lafayette", "food"],
        expected_min_sources=1,
        expected_metadata=["Phone", "Website", "Address"]
    ),
    TestCase(
        name="Semantic search (contextual embeddings)",
        query="mental health counseling for seniors",
        feature_tested="Contextual Retrieval",
        expected_keywords=["behavioral health", "mental health", "counseling"],
        expected_min_sources=1,
        expected_metadata=["Resource"]
    ),
    TestCase(
        name="Location filter extraction",
        query="food assistance in Orleans parish",
        feature_tested="Query Decomposition (Location Filter)",
        expected_keywords=["Orleans", "food"],
        expected_min_sources=1,
        expected_metadata=["County", "Parish"]
    ),
    TestCase(
        name="Complex multi-faceted query",
        query="mental health resources for seniors in Lafayette accepting Medicaid",
        feature_tested="Query Decomposition (Complex)",
        expected_keywords=["Lafayette", "mental health", "Medicaid"],
        expected_min_sources=1,
        expected_metadata=[]  # May not have exact match
    ),
    TestCase(
        name="Cross-sheet context discovery",
        query="24/7 crisis hotline or emergency mental health",
        feature_tested="Contextual Headers (Cross-Sheet)",
        expected_keywords=["crisis", "hotline", "24"],
        expected_min_sources=3,
        expected_metadata=["Phone"]
    ),
    TestCase(
        name="Phone prefix search with location",
        query="resources in Lafayette with phone numbers starting with 337",
        feature_tested="Phone Wildcard Search + Location Filter",
        expected_keywords=["Lafayette", "337"],
        expected_min_sources=2,
        expected_metadata=["Phone"]
    ),
    TestCase(
        name="Services field search",
        query="where can I get clothing and household items?",
        feature_tested="Services Field Indexing",
        expected_keywords=["clothing", "household"],
        expected_min_sources=1,
        expected_metadata=["Address"]
    ),
    TestCase(
        name="Eligibility field search",
        query="food banks that serve low-income families with children",
        feature_tested="Eligibility Field Indexing",
        expected_keywords=["food bank", "families", "children"],
        expected_min_sources=3,
        expected_metadata=["Phone", "Website"]
    ),
]


def call_chat_api(query: str, base_url: str = "http://localhost:8501") -> Dict:
    """Call the Streamlit chat API to get results.

    Note: This is a simplified version. In production, you'd integrate
    directly with the search_knowledge_base function or use a REST API.
    """
    # For now, we'll simulate by importing the search function
    # In production, this would be a REST API call
    try:
        # Import search function from Chat page
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent / "backend"))

        from pages.Chat import search_knowledge_base

        results = search_knowledge_base(query, top_k=5, use_hybrid=True)

        return {
            "success": True,
            "results": results,
            "count": len(results),
            "query": query
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "query": query
        }


def validate_test_case(test_case: TestCase, response: Dict) -> Dict:
    """Validate test case results against expectations."""

    if not response.get("success"):
        return {
            "passed": False,
            "reason": f"API call failed: {response.get('error')}",
            "details": {}
        }

    results = response.get("results", [])
    count = response.get("count", 0)

    # Check minimum sources
    if count < test_case.expected_min_sources:
        return {
            "passed": False,
            "reason": f"Expected at least {test_case.expected_min_sources} sources, got {count}",
            "details": {"source_count": count}
        }

    # Check for expected keywords in results
    all_text = " ".join([
        str(r.get("text", "")) + " " +
        str(r.get("resource_name", "")) + " " +
        str(r.get("services", ""))
        for r in results
    ]).lower()

    missing_keywords = [
        keyword for keyword in test_case.expected_keywords
        if keyword.lower() not in all_text
    ]

    # At least one keyword should match
    if len(missing_keywords) == len(test_case.expected_keywords):
        return {
            "passed": False,
            "reason": f"No expected keywords found in results",
            "details": {
                "expected_keywords": test_case.expected_keywords,
                "missing_all": True
            }
        }

    # Check for expected metadata fields in first result
    if test_case.expected_metadata and results:
        first_result = results[0]
        missing_metadata = [
            field for field in test_case.expected_metadata
            if field.lower() not in str(first_result).lower()
        ]

        if len(missing_metadata) == len(test_case.expected_metadata):
            return {
                "passed": False,
                "reason": f"Expected metadata fields not found",
                "details": {
                    "expected_metadata": test_case.expected_metadata,
                    "missing_metadata": missing_metadata
                }
            }

    return {
        "passed": True,
        "reason": "All validations passed",
        "details": {
            "source_count": count,
            "matched_keywords": [
                kw for kw in test_case.expected_keywords
                if kw.lower() in all_text
            ]
        }
    }


def run_test_suite(test_cases: List[TestCase], verbose: bool = False) -> Dict:
    """Run all test cases and return results."""

    results = {
        "total": len(test_cases),
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "test_results": []
    }

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task(
            "[cyan]Running Phase 1 regression tests...",
            total=len(test_cases)
        )

        for test_case in test_cases:
            progress.update(task, description=f"[cyan]Testing: {test_case.name}")

            start_time = time.time()
            response = call_chat_api(test_case.query)
            elapsed = time.time() - start_time

            validation = validate_test_case(test_case, response)

            test_result = {
                "name": test_case.name,
                "query": test_case.query,
                "feature": test_case.feature_tested,
                "passed": validation["passed"],
                "reason": validation["reason"],
                "details": validation["details"],
                "elapsed": elapsed
            }

            if validation["passed"]:
                results["passed"] += 1
            else:
                results["failed"] += 1

            results["test_results"].append(test_result)

            if verbose:
                status = "✅ PASS" if validation["passed"] else "❌ FAIL"
                console.print(f"{status} - {test_case.name} ({elapsed:.2f}s)")
                if not validation["passed"]:
                    console.print(f"  Reason: {validation['reason']}", style="red")

            progress.advance(task)

    return results


def print_summary(results: Dict):
    """Print test results summary."""

    console.print("\n")
    console.rule("[bold cyan]Phase 1 Regression Test Results")
    console.print("\n")

    # Summary table
    table = Table(title="Summary", show_header=True, header_style="bold magenta")
    table.add_column("Metric", style="cyan")
    table.add_column("Value", style="green")

    table.add_row("Total Tests", str(results["total"]))
    table.add_row("Passed", f"[green]{results['passed']}")
    table.add_row("Failed", f"[red]{results['failed']}")
    table.add_row(
        "Success Rate",
        f"{(results['passed'] / results['total'] * 100):.1f}%"
    )

    console.print(table)
    console.print("\n")

    # Detailed results table
    details_table = Table(
        title="Test Details",
        show_header=True,
        header_style="bold magenta"
    )
    details_table.add_column("Test", style="cyan", width=30)
    details_table.add_column("Feature", style="blue", width=25)
    details_table.add_column("Status", width=10)
    details_table.add_column("Time", width=8)
    details_table.add_column("Details", width=40)

    for test in results["test_results"]:
        status = "✅ PASS" if test["passed"] else "❌ FAIL"
        status_style = "green" if test["passed"] else "red"

        details_str = test["reason"]
        if test["details"].get("source_count"):
            details_str += f" (sources: {test['details']['source_count']})"

        details_table.add_row(
            test["name"],
            test["feature"],
            f"[{status_style}]{status}",
            f"{test['elapsed']:.2f}s",
            details_str
        )

    console.print(details_table)
    console.print("\n")

    # Feature coverage summary
    feature_table = Table(
        title="Feature Coverage",
        show_header=True,
        header_style="bold magenta"
    )
    feature_table.add_column("Feature", style="cyan")
    feature_table.add_column("Tests", style="green")
    feature_table.add_column("Status", style="yellow")

    features = {}
    for test in results["test_results"]:
        feature = test["feature"]
        if feature not in features:
            features[feature] = {"total": 0, "passed": 0}
        features[feature]["total"] += 1
        if test["passed"]:
            features[feature]["passed"] += 1

    for feature, stats in features.items():
        status = "✅ All Passed" if stats["passed"] == stats["total"] else "⚠️ Some Failed"
        feature_table.add_row(
            feature,
            f"{stats['passed']}/{stats['total']}",
            status
        )

    console.print(feature_table)


def main():
    parser = argparse.ArgumentParser(
        description="Phase 1 Advanced RAG Regression Testing"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output"
    )
    parser.add_argument(
        "--query", "-q",
        type=str,
        help="Run a single test query"
    )
    parser.add_argument(
        "--feature", "-f",
        type=str,
        help="Run tests for a specific feature only"
    )

    args = parser.parse_args()

    console.print("\n")
    console.rule("[bold cyan]Phase 1 Advanced RAG Regression Tests")
    console.print("\n")

    # Filter test cases if needed
    test_cases = TEST_CASES

    if args.query:
        # Run single query
        console.print(f"Running single query: [yellow]{args.query}")
        response = call_chat_api(args.query)
        console.print(response)
        return

    if args.feature:
        test_cases = [
            tc for tc in TEST_CASES
            if args.feature.lower() in tc.feature_tested.lower()
        ]
        console.print(f"Running tests for feature: [yellow]{args.feature}")
        console.print(f"Found {len(test_cases)} matching tests\n")

    # Run test suite
    results = run_test_suite(test_cases, verbose=args.verbose)

    # Print summary
    print_summary(results)

    # Exit with appropriate code
    exit_code = 0 if results["failed"] == 0 else 1

    if results["failed"] > 0:
        console.print(
            f"\n[red]❌ {results['failed']} test(s) failed[/red]",
            style="bold"
        )
    else:
        console.print(
            f"\n[green]✅ All {results['passed']} tests passed![/green]",
            style="bold"
        )

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
