# Maintainer Loop (cloud)

A self-running maintenance loop for ITSEZMONEY repos: wake on a trigger → triage
issues/PRs/CI → land low-risk work autonomously → escalate the rest → record
state in a ledger issue. Built on two committed skills and **Claude Code
Routines** (Anthropic's cloud automation), so it keeps running with no laptop
open.

- Playbook: [`.claude/skills/maintainer-orchestrator`](../.claude/skills/maintainer-orchestrator/SKILL.md)
- Triage: [`.claude/skills/github-project-triage`](../.claude/skills/github-project-triage/SKILL.md)

## How it maps to "wake every 5 min, direct work to threads"

| Your model | Cloud equivalent |
| --- | --- |
| Always-on driver | A **Routine** on Anthropic's cloud (no laptop). |
| Wake every N minutes | Routine **trigger** (schedule / GitHub event / API). |
| Triage + classify | `github-project-triage` skill. |
| Direct work to threads | Orchestrator fans out per-repo work with the `Agent` tool; mutations stay on one thread. |
| Some work lands autonomously | Routines run with **no permission prompts**; autonomy policy gates what merges. |
| Steer / report | The `🤖 Maintainer Loop — Ledger` issue (durable across runs). |

## ⚠️ Cadence reality check

Claude Code Routine **scheduled** triggers have a **one-hour minimum** — a true
"every 5 minutes" schedule is rejected. Pick a trigger based on how reactive you
need to be:

| Want | Use | Notes |
| --- | --- | --- |
| Steady backlog sweeps | **Scheduled** trigger | Hourly is the floor; daily/weeknightly is usually plenty and cheaper. |
| Real-time on PRs/releases | **GitHub event** trigger | Fires on `pull_request.*` / `release.*` — the closest thing to "instant". Subject to per-account hourly caps. |
| Literal 5-minute polling | **API** trigger + external pinger | Your own cron/codex driver POSTs to the routine's `/fire` endpoint every 5 min. This is where a 5-min cadence actually lives. |

You can attach **several triggers to one routine** — e.g. hourly sweep *plus*
react to every new PR *plus* an API endpoint your driver can poke.

## Setup (once per loop)

Routines can't be created from inside a web session or via API — create them in
the UI or with `/schedule` from a local CLI.

1. **Commit the skills.** They must live in the repo(s) the routine clones —
   that's what this PR does. The fan-out script (below) copies them to every
   ITSEZMONEY repo.
2. **Create the routine** at <https://claude.ai/code/routines> → **New routine**:
   - **Repositories:** select the repos to maintain. One routine can clone
     several, so a single org-maintainer routine can sweep them all in one run.
   - **Environment:** `Default` (Trusted network) is fine. Add `DATABASE_URL`,
     `ANTHROPIC_API_KEY`, etc. only if a run needs to actually build/run the app.
   - **Connectors:** keep **GitHub**; drop the rest unless a run needs them.
   - **Permissions:** enable **Allow unrestricted branch pushes** only if you
     want it to push to existing branches; PR-merge of low-risk items works
     without it.
   - **Prompt:** paste the kickoff prompt below.
   - **Trigger:** pick from the cadence table above.
3. **Run now** once to seed the ledger issue and confirm behavior, then let the
   trigger drive it.

> Identity note: a routine acts as **you** — commits, PRs, and merges carry your
> GitHub user, and it draws down your account's usage + daily routine-run cap.

### Kickoff prompt (paste into the routine)

```
Load the maintainer-orchestrator skill and run one maintenance pass over every
repository cloned for this run, following the skill's loop and autonomy policy
exactly: triage, read/update the "🤖 Maintainer Loop — Ledger" issue, act per
the autonomy rules below, then summarize the run in the ledger.

SCOPE GUARD
- Only operate on repositories whose owner is `adityash8` or `ITSEZMONEY`.
- If a cloned repo is outside those owners, skip it entirely (no triage, no
  merge, no PR) and log the skip in the run output (not the skipped repo's ledger).

TRUSTED AUTHOR — explicit allowlist, not "CI is green"
- An item is from a "trusted author" ONLY if the PR author is one of:
  `adityash8`. No one else qualifies — first-time/external contributors,
  forks, and bot accounts (including dependabot, renovate) are NOT trusted.
- Dependency PRs from bots may be AUTO-MERGED only when they also pass every
  low-risk gate below; bot authorship alone never grants trust for anything else.

AUTONOMY
- AUTO-MERGE only when ALL hold: CI fully green; change is limited to
  deps/docs/tests/lockfile/formatting; small diff; touches NONE of
  auth/payments/certs/schema/CI/secrets/infra; and author is trusted (above)
  OR it's a bot dependency bump meeting these same gates.
- Everything else: open a DRAFT PR and apply the `needs-owner` label. Do not merge.
- Defer or close stale or duplicate items.
- Never make product, pricing, or architecture decisions. When in doubt,
  escalate (draft + needs-owner) instead of merging.
```

## Autonomy policy (summary)

Authorized level: **auto-merge low-risk**. Full rules in the orchestrator skill.

- **Scope guard:** only repos owned by `adityash8` or `ITSEZMONEY`; skip and log
  anything else.
- **Trusted author = `adityash8` only.** Other org members, external/first-time
  contributors, forks, and bots (Dependabot/Renovate) are **untrusted**.
- **Auto-merge** (squash) only when *all* hold: CI green · change is
  deps/docs/tests/lockfile/formatting/safe-config · small bounded diff · touches
  none of {auth, Stripe, `certificates/`, schema/migrations, CI/release, infra,
  `.env*`, secrets} · author trusted (or loop-authored) **or** a bot dependency
  bump meeting all these gates · no unresolved change requests.
- **Draft PR + `needs-owner`** for anything else — bugs with real logic, features,
  protected surfaces, big diffs, untrusted authors, uncertain CI, any ambiguity.
- **Never** touch certs/keys/secrets, force-push protected branches, close an
  item under active discussion, or make product/pricing/architecture decisions.

## Fan out / sync to all repos

The skill lives in each repo's `.claude/skills/`, so propagation = copy the
**current `gate-slip` versions** over the top of every target repo. The target
list is `scripts/maintainer-target-repos.txt` (the 27 other ITSEZMONEY repos +
the adityash8 repos; `gate-slip` is the source, not a target).

> ⚠️ **Overwrite, don't skip.** Every target already contains
> `.claude/skills/maintainer-orchestrator/`, so any "skip if it exists" logic
> propagates **nothing** — that's how repos get stuck on an old skill version.
> Both paths below overwrite and only open a PR where content actually changed.

### A. Distributor routine (cross-owner, no local `gh`)

A one-off Routine with **every target repo *plus* `gate-slip` selected** (it
copies *from* the gate-slip checkout). Prompt:

```
gate-slip holds the canonical maintainer-loop files at
.claude/skills/maintainer-orchestrator/, .claude/skills/github-project-triage/,
and docs/MAINTAINER_LOOP.md. For every OTHER cloned repo, copy those three paths
from the gate-slip checkout OVER the top of whatever is there. If nothing changed
(already identical), skip that repo. Otherwise create/update branch
chore/maintainer-loop, commit "chore: sync maintainer loop skills", and open or
update a DRAFT PR titled "Sync maintainer loop skills". Do not modify gate-slip.
Report each repo as created / updated / unchanged, with the PR URL.
```

### B. Shell script (`gh`, cross-owner)

```bash
scripts/fanout-maintainer-skills.sh                    # all repos in scripts/maintainer-target-repos.txt
scripts/fanout-maintainer-skills.sh ITSEZMONEY/serum adityash8/llmx   # explicit owner/repo
```

It copies over the top and opens a PR only where content changed (idempotent).

After either path, **add every repo to the maintainer routine's repo list** so
the loop actually runs against them.

## Alternative: GitHub Actions (true 5-min, BYO key)

If you'd rather not depend on Routines for sub-hour cadence, a scheduled Action
(`on: schedule: cron`, 5-min floor) can run the Claude Code GitHub Action with
the same kickoff prompt and an `ANTHROPIC_API_KEY` secret. It's more setup and
burns Action minutes + API spend per repo, so prefer Routines unless you need
the tighter cadence in CI. See <https://code.claude.com/docs/en/github-actions>.

## References

- Routines / scheduled tasks: <https://code.claude.com/docs/en/web-scheduled-tasks>
- Claude Code on the web: <https://code.claude.com/docs/en/claude-code-on-the-web>
- Skills: <https://code.claude.com/docs/en/skills>
