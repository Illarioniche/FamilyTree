#!/usr/bin/env python3
"""Discover the existing synchronous XCTest methods without copying test bodies.

Unsupported declarations fail closed. Swift itself validates all assertion APIs,
imports, method accessibility, conditional compilation, and callback signatures.
"""
from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise SystemExit("Cannot discover CLI tests: " + message)


def main() -> None:
    if len(sys.argv) != 3:
        fail("expected TEST_DIRECTORY and OUTPUT_FILE")
    directory, output = map(Path, sys.argv[1:])
    tests = []
    for source in sorted(directory.glob("*.swift")):
        text = source.read_text(encoding="utf-8")
        classes = re.findall(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\s*\{", text, re.M)
        methods = re.findall(r"\bfunc\s+(test\w+)\b([^\{]*)\{", text)
        if not methods:
            continue
        if len(classes) != 1:
            fail(f"{source.name}: expected exactly one XCTestCase subclass")
        if re.search(r"\bfunc\s+(?:setUp|tearDown)\w*[^\{]*\basync\b", text):
            fail(f"{source.name}: async lifecycle requires the real XCTest runner")
        for method, signature in methods:
            if not re.fullmatch(r"\s*\(\s*\)\s*(?:throws\s*)?", signature):
                fail(f"{source.name}: unsupported signature for {method}; use swift test")
            tests.append((classes[0], method, "throws" in signature))
    if not tests:
        fail("no tests found")
    identifiers = [f"{cls}.{method}" for cls, method, _ in tests]
    if len(set(identifiers)) != len(identifiers):
        fail("duplicate test identifiers")
    calls = []
    for cls, method, throwing in tests:
        calls.append(
            f'        CLIHarness.run("{cls}.{method}", make: {{ {cls}() }}) '
            f'{{ test in {"try " if throwing else ""}test.{method}() }}'
        )
    output.write_text(
        "import Foundation\nimport XCTest\n\n"
        "@main struct CoreCheckRunner {\n"
        "    static func main() {\n"
        '        if CommandLine.arguments.contains("--verify-harness") {\n'
        "            exit(CLIHarness.verifyHarness())\n"
        "        }\n"
        f'        print("Running {len(tests)} core tests with the CLI XCTest compatibility runner…")\n'
        + "\n".join(calls)
        + "\n        exit(CLIHarness.finish())\n    }\n}\n",
        encoding="utf-8",
    )
    print(f"Discovered {len(tests)} XCTest methods in {len(set(cls for cls, _, _ in tests))} suites.")


if __name__ == "__main__":
    main()
