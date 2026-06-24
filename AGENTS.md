# Agent Instructions

Use the current repository state as the source of truth for this project.

When there is a conflict, resolve it in this order:
1. Code, scripts, configuration, and tests in this repository.
2. Repository documentation that matches the current codebase.
3. Prior assistant memory, cached context, or assumptions from earlier sessions.

If repository files conflict with each other, stop treating memory as authoritative and
prefer the implementation that is actually exercised by the current code path. Flag the
inconsistency explicitly before making broader assumptions.
