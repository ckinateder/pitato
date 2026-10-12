---
description: Review code changes (read-only)
argument-hint: "[git range or focus]"
---
Review the code changes in this repository. Do NOT edit, create or delete files, and do not run commands that modify the repo.

User input (may be a git range or commit, a focus area, or none): ${@:-none}

1. Find the changes. If the input names a git range or commit, review that. Otherwise review `git diff HEAD` plus untracked files from `git status --short`. If there are no changes, say so and stop. If the diff is large, review it file by file.
2. Read the surrounding code, not just the diff, so you judge changes in context.
3. Report findings ordered by severity: correctness bugs, security issues, error handling, missing tests, then style. For each give `file:line`, what is wrong, and a concrete suggested fix. If the input names a focus area, prioritise it.
4. Only report issues you can point to in the code. Say so when a point is uncertain. If nothing is wrong, say that rather than inventing nitpicks.

Finish with a one-line verdict: approve, approve with nits, or changes requested.
