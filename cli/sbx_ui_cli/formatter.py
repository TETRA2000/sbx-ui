"""Terminal output formatting with colored tables.

Provides rich-looking output using ANSI escape codes (no external
dependencies). Falls back to plain text when not connected to a TTY.
"""

from __future__ import annotations

import os
import sys
from typing import Optional


# ANSI color codes
class _Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"
    BRIGHT_GREEN = "\033[92m"
    BRIGHT_RED = "\033[91m"
    BRIGHT_YELLOW = "\033[93m"
    BRIGHT_CYAN = "\033[96m"


def _use_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    return sys.stdout.isatty()


def _c(text: str, *codes: str) -> str:
    if not _use_color():
        return text
    return "".join(codes) + text + _Colors.RESET


def bold(text: str) -> str:
    return _c(text, _Colors.BOLD)


def dim(text: str) -> str:
    return _c(text, _Colors.DIM)


def green(text: str) -> str:
    return _c(text, _Colors.GREEN)


def red(text: str) -> str:
    return _c(text, _Colors.RED)


def yellow(text: str) -> str:
    return _c(text, _Colors.YELLOW)


def cyan(text: str) -> str:
    return _c(text, _Colors.CYAN)


def bright_green(text: str) -> str:
    return _c(text, _Colors.BRIGHT_GREEN)


def bright_red(text: str) -> str:
    return _c(text, _Colors.BRIGHT_RED)


def status_color(status: str) -> str:
    """Color-code a sandbox status string."""
    s = status.lower()
    if s == "running":
        return bright_green(status)
    elif s == "stopped":
        return dim(status)
    elif s == "creating":
        return yellow(status)
    elif s == "removing":
        return yellow(status)
    return status


def decision_color(decision: str) -> str:
    """Color-code a policy decision."""
    d = decision.lower()
    if d == "allow":
        return green(decision)
    elif d == "deny":
        return red(decision)
    return decision


def print_table(
    headers: list[str],
    rows: list[list[str]],
    *,
    color_cols: Optional[dict[int, callable]] = None,
) -> None:
    """Print a formatted table with auto-sized columns.

    Args:
        headers: Column header strings.
        rows: List of rows, each a list of cell strings.
        color_cols: Optional mapping of column index -> color function,
                    applied after width calculation (so ANSI codes don't
                    affect alignment).
    """
    if not rows:
        print(dim("  (none)"))
        return

    color_cols = color_cols or {}

    # Calculate column widths from raw text
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell))

    # Add padding
    widths = [w + 2 for w in widths]

    # Print header
    header_line = "".join(
        bold(h.ljust(widths[i])) for i, h in enumerate(headers)
    )
    print(header_line)

    # Print rows
    for row in rows:
        parts = []
        for i, cell in enumerate(row):
            padded = cell.ljust(widths[i]) if i < len(widths) else cell
            if i in color_cols:
                # Apply color after padding so ANSI codes don't affect width
                padded = color_cols[i](cell).ljust(
                    widths[i] + _ansi_overhead(color_cols[i](cell), cell)
                )
            parts.append(padded)
        print("".join(parts))


def _ansi_overhead(colored: str, plain: str) -> int:
    """Calculate the extra bytes added by ANSI codes."""
    return len(colored) - len(plain)


def print_success(message: str) -> None:
    print(bright_green("✓") + " " + message)


def print_error(message: str) -> None:
    print(bright_red("✗") + " " + message, file=sys.stderr)


def print_info(message: str) -> None:
    print(cyan("→") + " " + message)


def print_section(title: str) -> None:
    print()
    print(bold(title))
    print(dim("─" * len(title)))
