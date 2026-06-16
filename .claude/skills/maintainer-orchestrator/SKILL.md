---
name: maintainer-orchestrator
description: >-
  Control-plane loop for maintaining ITSEZMONEY repositories. Use when asked to
  "maintain the repos", "run the maintainer loop", "triage and act on the
  backlog", or when invoked by a scheduled/API/GitHub-event cloud Routine. It
  inspects issues/PRs/CI across one or more repos, classifies each item as
  autonomous / needs-owner / defer, lands low-risk work autonomously, escalates
  the rest, and records state in a durable ledger issue.
---

# Maintainer Orchestrator

A **control-plane** skill: inspect, classify, act, monitor, and report. It does
not invent product direction — it moves the existing backlog toward a clean,
green, reviewed state and escalates anything that needs a human decision.

This skill is designed to run **autonomously inside a Claude Code Routine**
(`claude.ai/code/routines`) — a cloud session with no permission prompts — but
also works when invoked by hand in an interactive session.

## The loop (one run)

Each run is one pass. Do these in order, then stop.

1. **Scope (owner-guarded).** Determine the target repositories.
   - If the Routine cloned multiple repos, act on all of them; if invoked in a
     single repo with a GitHub remote, act on that repo only.
   - **Owner allowlist:** only operate on repos whose owner is `adityash8` or
     `ITSEZMONEY`. Skip any cloned repo outside those owners entirely — no
     triage, no PR, no merge — and record the skip in the **run summary**, never
     in the skipped repo (you have no business writing to it).
   - Do **not** broaden beyond the cloned/selected repos unless the prompt says
     `all` / `org-wide`.
2. **Triage.** Invoke the `github-project-triage` skill to build item cards for
   every open issue and PR (URL, what/why, author trust, fit, risk, proof/test
   state, blockers, next action) and sort them into three buckets:
   **autonomous · needs-owner · defer/close**.
3. **Read the ledger (single, race-safe).** Locate the repo's ledger by the
   `maintainer-ledger` label (canonical), falling back to the exact title
   `🤖 Maintainer Loop — Ledger`. **Exactly one must stay open.** If several are
   open — two runs can race and each create one — keep the **lowest-numbered**
   open ledger, close the rest as duplicates (`state_reason: duplicate` with
   `duplicate_of` set to the survivor), and continue on the survivor. If none exists, create it, ensure the
   `maintainer-ledger` label exists, and apply it. Never open a second ledger
   when one is already open. The ledger is the durable memory across runs (cloud
   sessions are ephemeral); skip anything it marks resolved or `wontfix`.
4. **Act on autonomous items**, one at a time, verifying each before moving on
   (see *Autonomy policy* below). Stop touching an item the moment it stops
   meeting the bar and reclassify it as needs-owner.
5. **Escalate needs-owner items.** Don't guess at product/direction/secret
   decisions. Label `needs-owner`, leave a one-paragraph comment stating the
   decision required and the options, and record it in the ledger.
6. **Defer/close** stale, duplicate, or superseded items with a short reason.
7. **Report.** Update the ledger issue with what changed this run (landed,
   escalated, deferred, still-in-flight) and the timestamp. Keep it skimmable.

Then end the run. The next trigger starts the next pass.

## Autonomy policy

The owner has authorized **auto-merge for low-risk work**. Be conservative:
when in doubt, downgrade to a draft PR and escalate.

### Low-risk → may land autonomously (open PR, get CI green, then merge)

ALL must hold:
- CI is **fully green** on the head commit (not pending, not skipped-as-proxy).
- The change is one of: dependency patch/minor bump that is non-breaking,
  lockfile sync, docs/comments/typo, formatting or lint autofix, test-only
  additions, or a clearly-scoped config tweak.
- Diff is small and bounded (rule of thumb: ≤ ~50 changed lines, single
  concern).
- It touches **none** of: auth, payments/Stripe, `certificates/` or any
  key/secret, DB schema or migrations (`shared/schema.ts`, drizzle), CI/release
  config, infra/deployment config, or anything in `.env*`.
- Author is **trusted** per the allowlist below (or the change was authored by
  this loop, which runs as `adityash8`) — **or** it is a bot dependency bump that
  independently meets every other gate in this list.
- No unresolved review thread requests changes.
- Branch is up to date with base (or can be safely fast-forward updated).

**Trusted author — explicit allowlist, not "CI is green":**
- An item counts as from a trusted author **only** if the PR author is
  `adityash8`. No one else qualifies — other org members, first-time/external
  contributors, forks, and bot accounts (including Dependabot/Renovate) are
  **not** trusted.
- Bot **dependency** PRs may be auto-merged **only** when they also pass every
  low-risk gate above; bot authorship alone never grants trust for anything else.

For these: ensure CI is green, then **merge** (squash by default). If the loop
authored the fix, open the PR first, let CI run, then merge once green.

### Everything else → draft PR + escalate, never auto-merge

Bugs with real logic changes, features, anything touching the protected areas
above, large diffs, untrusted authors, red/uncertain CI, or any ambiguity:
open or leave a **draft** PR with your analysis, label `needs-owner`, and record
it in the ledger. Do not merge.

### Never

- Force-push to or merge into protected/long-lived branches outside the PR flow.
- Touch certificates, private keys, or secrets.
- Close an item a human is actively discussing.
- Make product/pricing/architecture decisions.

## CI babysitting

When you open or own a PR, drive its CI to green: read failing job logs,
reproduce locally when possible, push the fix, re-check. Re-kick on each failure
rather than treating one round as the job. If a failure is real and out of scope
or you've re-kicked several times without progress, escalate with the diagnosis
instead of looping forever.

## Parallelization (worker fan-out)

Within a single run you may fan out read-only investigation across repos/items
using the `Agent` tool (one subagent per repo or per cluster of related items).
Keep **mutations** (commits, merges, comments) on the main orchestrator thread so
there is a single writer. Workers investigate and report; the orchestrator
decides and acts. Workers must not spawn further workers.

## Tools

Use the **GitHub MCP connector** for all GitHub reads/writes (issues, PRs, CI
status, job logs, merges, comments, labels); fall back to `gh` only if the
connector is unavailable. Use `git` for local branch work. The `github-project-triage`
skill provides the queue-discovery and scoring helpers.

Close duplicate ledgers via the connector/REST API so `state_reason: duplicate`
(+ `duplicate_of`) sticks — verified working. Note `gh issue close --reason`
accepts only `completed`/`not_planned`, so if you must use `gh`, close with
`not_planned` and a comment linking the survivor instead.

## The ledger

One ledger issue per repo, marked with the `maintainer-ledger` label (the
canonical identifier) and titled `🤖 Maintainer Loop — Ledger`. **Exactly one
stays open** — if a run finds duplicates it keeps the lowest-numbered open one,
closes the others as duplicates, and rewrites the survivor's body. Locate by
label first (titles can be edited), then by title. Body rewritten each run.
Suggested shape:

```
## Maintainer Loop — last run <UTC timestamp>

### Landed this run
- #123 bump zod 3.x → 3.y (deps, CI green) — merged

### Needs owner
- #130 Stripe webhook retry policy — needs decision: idempotency window? (options A/B)

### In flight
- #128 fix PDF parse crash — draft PR open, CI red, investigating

### Deferred / closed
- #99 closed as duplicate of #128
```

This is the only state that survives between runs — keep it accurate.

> Seeing duplicate ledgers? That means two runs started concurrently — check the
> routine's triggers for overlap (e.g. a manual **Run now** firing alongside a
> scheduled run, or two schedule/event triggers). The dedup above heals it, but
> overlapping triggers also burn double the runs.

## Reporting back to the owner

A Routine run has no human present, so "escalation" means: the `needs-owner`
label, a concise comment on the item, and a ledger entry. Do not block on
`AskUserQuestion` (there is nobody to answer mid-run). If a connector is
configured (Slack/Linear/etc.), a one-line summary of escalations is welcome,
but the ledger is the source of truth.
