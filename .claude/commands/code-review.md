Review target: $ARGUMENTS

If $ARGUMENTS is a GitHub PR URL or repo/pull/number:
- Use `gh` to fetch the PR diff and description
- Focus review on changed lines only
- Post the review as a PR comment using `gh pr comment`

Otherwise:
- Interpret $ARGUMENTS as a description of what to review
- Use git log, git diff, or file reads as appropriate to 
  find the relevant changes

Then apply the standard review criteria:

Before starting the review, read the following for context:
- `.claude/CLAUDE.md` for coding standards and the privacy invariant
- Any design documents in /designs/ folder relevant to files being changed
- use the designs documents for module intent and architecture

Then perform a code review of the current PR focusing on:
- Bugs and logic errors
- CLAUDE.md violations
- Deviations from the documented architecture/design intent from the designs documents
- Swift/iOS best practices (memory management, concurrency)
- Kotlin/Android: coroutine and lifecycle correctness
- Python: type hints, error handling, async patterns if applicable
- Code and logic duplication, opportunity for optimisation and consolidation
- Check for simplicity, maintainability and extensibility
- Privacy: passenger/crew/document data logged, persisted server-side, or sent somewhere new; `PRIVACY.md` not updated when what is collected changes
- Form output: mapping/template changes that reach more airports than intended (match order exact ICAO → `icao_list` → prefix → default); golden snapshots regenerated without the change being intended
- Sync: SwiftData model changes that aren't CloudKit-compatible (non-optional without default, unique constraints, non-optional relationships)
- User-facing strings missing from the String Catalogs or their FR/DE/ES entries

Do NOT flag:
- Style issues not covered by CLAUDE.md
- Minor suggestions or nits
- Pre-existing issues not touched by this PR

Be concise. High confidence issues only.

If no issues found, post a brief approval comment.

## Output format (machine-read — do not restyle)

`/process-review` and `/land-pr` find this comment by matching on its first line,
so the comment shape is a contract, not a stylistic choice. Emit exactly this
skeleton and do not substitute bold, plain text, or a different heading level:

```markdown
## Code Review

<one- or two-sentence summary of what was reviewed>

### Critical
- `path/to/file.py:123` — <finding>

### Important
- `path/to/File.swift:45` — <finding>

### Minor
- `path/to/file.py:67` — <finding>
```

Rules:

- The **first line is always exactly `## Code Review`** — including for a clean
  review, which follows it with a brief approval line and no severity sections.
- Severity headings are `### Critical` / `### Important` / `### Minor`.
- **Omit a severity section entirely when it has no findings** — no empty heading
  or "none" placeholder.
- Findings are list items; lead each with the file path (and line where known).
