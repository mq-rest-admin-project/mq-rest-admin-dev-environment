# Multi-version MQ testing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the MQ dev environment select among multiple MQ versions
(9.4.5 and 10.0) from a single JSON manifest, run one version per run on
the stable contract ports, and expose the resolved version to CI matrices
and tests.

**Architecture:** A single `mq-versions.json` manifest is the source of
truth. A sourced bash helper (`mq_resolve_version.sh`) resolves an alias
to an image tag, capability list, and a per-version Compose project name,
exporting them for the lifecycle scripts. A second helper emits the
version list as JSON for GitHub Actions matrices. The `setup-mq` action
gains a `mq-version` input and version/image/caps outputs; a reusable
workflow publishes the matrix. Plain-bash tests under `tests/` cover the
helpers and run in a dedicated CI workflow.

**Tech Stack:** Bash, `jq` (already in the validation container), Docker
Compose, GitHub Actions (composite action + reusable workflow).

## Global Constraints

Every task's requirements implicitly include this section.

- **Work only inside the worktree:** `.worktrees/issue-157-multi-version-mq/`
  on branch `feature/157-multi-version-mq`. The main worktree is read-only.
- **Git/GitHub wrappers only:** use `vrg-git` (not `git`), `vrg-gh` (not
  `gh`), and `vrg-commit` for commits. Raw `git commit` is denied.
  `vrg-commit` signature: `vrg-commit --type <feat|fix|docs|style|refactor|test|chore|ci|build|revert> --scope <scope> --message <msg> [--body <body>]`.
- **Commit trailer:** end every commit body with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **No heredocs in Bash tool calls** (`<<EOF` is blocked) — create files
  with the editor/Write tool, not `cat <<EOF`.
- **Validation is one command, run from the worktree:**
  `vrg-container-run -- vrg-validate` (runs markdownlint, shellcheck,
  yamllint, actionlint). Do not invoke linters individually.
- **Run the bash tests explicitly:** `bash tests/<name>.sh` from the
  worktree root (CWD = repo root).
- **`jq` is the only new dependency.** It is present in CI and the
  container; it becomes a declared local prerequisite. Do not add `yq`,
  `bats`, or any other tool.
- **Manifest is JSON** (`mq-versions.json`) — no comments allowed in the
  file; rationale lives in docs.
- **`default` stays `"9.4.5"`.** Flipping the default to `"10.0"` is a
  follow-up gated on `mq-rest-admin-common#217` and is NOT part of this
  plan.
- **Contract invariance:** ports (9443/9444, 1414/1415), queue-manager
  names (QM1/QM2), and users (`mqadmin`/`mqreader`) do not change.
- **Consumption ref:** consumers track the rolling `vX.Y` major-minor tag
  (documentation only in this plan; no release is cut here).
- **Spec:** `docs/plans/2026-06-23-multi-version-mq-testing-design.md`.

---

## File Structure

**Create:**
- `mq-versions.json` — version manifest (source of truth).
- `scripts/mq_resolve_version.sh` — sourced helper: alias → `MQ_IMAGE`,
  `MQ_VERSION`, `MQ_CAPS`, `COMPOSE_PROJECT_NAME`; also a CLI print mode.
- `scripts/mq_versions_matrix.sh` — prints the version list as a JSON
  array for Actions matrices.
- `.github/workflows/mq-versions.yml` — reusable workflow emitting
  `versions` + `default` outputs.
- `.github/workflows/shell-tests.yml` — runs `tests/*.sh` on PRs.
- `tests/fixtures/mq-versions.json` — stable fixture manifest for tests.
- `tests/test_manifest.sh` — validates the real manifest's structure.
- `tests/test_resolve_version.sh` — covers the resolve helper.
- `tests/test_versions_matrix.sh` — covers the matrix helper.
- `tests/test_lifecycle_wiring.sh` — covers project-name propagation via
  a stubbed `docker`.

**Modify:**
- `scripts/mq_start.sh`, `scripts/mq_stop.sh`, `scripts/mq_reset.sh`,
  `scripts/mq_seed.sh`, `scripts/mq_verify.sh` — source the resolve
  helper.
- `.github/actions/setup-mq/action.yml` — `mq-version` input;
  version/image/caps outputs; project-name becomes a prefix.
- `CLAUDE.md`, `README.md`, `docs/site/docs/architecture/environment-contract.md`
  — document version selection, `jq` prerequisite, and version signals.

**Unchanged:** `scripts/mq_wait_ready.sh` (uses stable ports only),
`config/docker-compose.yml` (already reads `${MQ_IMAGE:-...}`).

---

## Task 1: Version manifest + manifest validity test

**Files:**
- Create: `mq-versions.json`
- Test: `tests/test_manifest.sh`

**Interfaces:**
- Produces: `mq-versions.json` with shape
  `{ "default": <alias>, "versions": { <alias>: { "image": <str>, "caps": [<str>...] } } }`.
  Consumed by Tasks 2 and 3.

- [ ] **Step 1: Write the failing test**

Create `tests/test_manifest.sh`:

```bash
#!/usr/bin/env bash
# Validates the real mq-versions.json manifest structure.
set -uo pipefail

MANIFEST="mq-versions.json"
fails=0
check() { # description, condition-exit-code
  if [ "$2" -eq 0 ]; then echo "ok   - $1"; else echo "FAIL - $1"; fails=$((fails + 1)); fi
}

jq -e . "$MANIFEST" >/dev/null 2>&1; check "manifest is valid JSON" $?

jq -e '.default as $d | .versions | has($d)' "$MANIFEST" >/dev/null 2>&1
check "default names an existing version" $?

jq -e '.versions | to_entries | all(.value.image | type == "string" and length > 0)' \
  "$MANIFEST" >/dev/null 2>&1
check "every version has a non-empty image" $?

jq -e '.versions | to_entries | all(.value.caps | type == "array")' \
  "$MANIFEST" >/dev/null 2>&1
check "every version has a caps array" $?

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails check(s) failed"; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifest.sh`
Expected: FAIL — `jq` errors because `mq-versions.json` does not exist
(non-zero exit, "failed" output).

- [ ] **Step 3: Create the manifest**

Create `mq-versions.json`:

```json
{
  "default": "9.4.5",
  "versions": {
    "9.4.5": {
      "image": "icr.io/ibm-messaging/mq:9.4.5.1-r1",
      "caps": []
    },
    "10.0": {
      "image": "icr.io/ibm-messaging/mq:10.0.0.0-r1",
      "caps": ["chstatus-quantum-safe"]
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_manifest.sh`
Expected: PASS — all four checks `ok`, final line `PASS`.

- [ ] **Step 5: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: completes clean (shellcheck passes on the new test script).

- [ ] **Step 6: Commit**

```bash
vrg-git add mq-versions.json tests/test_manifest.sh
vrg-commit --type feat --scope versions --message "add MQ version manifest" --body "$(printf 'Single source of truth mapping version aliases to image tags and\ncapability tokens, with a default. Defaults to 9.4.5; the 10.0 default\nflip is gated on mq-rest-admin-common#217.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 2: Version-resolve helper

**Files:**
- Create: `scripts/mq_resolve_version.sh`
- Create: `tests/fixtures/mq-versions.json`
- Test: `tests/test_resolve_version.sh`

**Interfaces:**
- Consumes: a manifest at `$MQ_VERSIONS_FILE` (default `mq-versions.json`).
- Produces:
  - Function `mq_resolve <alias|"">` — when sourced, exports
    `MQ_VERSION` (resolved alias), `MQ_IMAGE` (image tag), `MQ_CAPS`
    (compact JSON array), `COMPOSE_PROJECT_NAME`
    (`${MQ_PROJECT_NAME_PREFIX:-mq-dev}-<slug>`, slug = alias with `.`→`_`).
    Empty/absent alias resolves the manifest `default`. Unknown alias →
    message on stderr listing valid versions + non-zero return.
  - CLI: `scripts/mq_resolve_version.sh [alias]` prints the resolved
    image tag to stdout (used by tests and humans).
  - These names are relied on by Task 4 (lifecycle scripts) and Task 5
    (action).

- [ ] **Step 1: Write the fixture**

Create `tests/fixtures/mq-versions.json` (distinct image values so tests
bind to the fixture, not the real manifest):

```json
{
  "default": "9.4.5",
  "versions": {
    "9.4.5": { "image": "test/mq:9.4.5", "caps": [] },
    "10.0": { "image": "test/mq:10.0", "caps": ["chstatus-quantum-safe"] }
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_resolve_version.sh`:

```bash
#!/usr/bin/env bash
# Covers scripts/mq_resolve_version.sh in both CLI and sourced modes.
set -uo pipefail

export MQ_VERSIONS_FILE="tests/fixtures/mq-versions.json"
HELPER="scripts/mq_resolve_version.sh"
fails=0
eq() { # description, actual, expected
  if [ "$2" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1: expected [$3] got [$2]"; fails=$((fails + 1)); fi
}
ok_nonzero() { # description, exit-code
  if [ "$2" -ne 0 ]; then echo "ok   - $1"
  else echo "FAIL - $1: expected non-zero exit"; fails=$((fails + 1)); fi
}

# CLI mode: explicit alias prints its image.
eq "cli resolves 10.0 image" "$(bash "$HELPER" 10.0)" "test/mq:10.0"

# CLI mode: no alias uses the manifest default (9.4.5).
eq "cli no-arg uses default image" "$(bash "$HELPER")" "test/mq:9.4.5"

# CLI mode: unknown alias fails and names valid versions.
err="$(bash "$HELPER" bogus 2>&1)"; rc=$?
ok_nonzero "cli unknown alias exits non-zero" "$rc"
case "$err" in
  *"unknown MQ version"*"9.4.5"*"10.0"*) echo "ok   - error lists valid versions" ;;
  *) echo "FAIL - error message missing valid versions: $err"; fails=$((fails + 1)) ;;
esac

# Sourced mode: exports the full signal set for 10.0.
( set -e
  # shellcheck disable=SC1090
  source "$HELPER"
  mq_resolve 10.0
  [ "$MQ_VERSION" = "10.0" ] || { echo "FAIL - sourced MQ_VERSION"; exit 1; }
  [ "$MQ_IMAGE" = "test/mq:10.0" ] || { echo "FAIL - sourced MQ_IMAGE"; exit 1; }
  [ "$MQ_CAPS" = '["chstatus-quantum-safe"]' ] || { echo "FAIL - sourced MQ_CAPS [$MQ_CAPS]"; exit 1; }
  [ "$COMPOSE_PROJECT_NAME" = "mq-dev-10_0" ] || { echo "FAIL - sourced project name [$COMPOSE_PROJECT_NAME]"; exit 1; }
  echo "ok   - sourced mode exports version/image/caps/project"
) || fails=$((fails + 1))

# Sourced mode: 9.4.5 caps default to [].
( set -e
  # shellcheck disable=SC1090
  source "$HELPER"
  mq_resolve 9.4.5
  [ "$MQ_CAPS" = "[]" ] || { echo "FAIL - 9.4.5 caps [$MQ_CAPS]"; exit 1; }
  echo "ok   - 9.4.5 caps default to []"
) || fails=$((fails + 1))

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails check(s) failed"; exit 1; }
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/test_resolve_version.sh`
Expected: FAIL — `scripts/mq_resolve_version.sh` does not exist.

- [ ] **Step 4: Write the helper**

Create `scripts/mq_resolve_version.sh`:

```bash
#!/usr/bin/env bash
# Resolve an MQ version alias to its image, caps, and Compose project name.
#
# Source it and call mq_resolve to export the environment for the
# lifecycle scripts, or run it directly to print the resolved image:
#   source scripts/mq_resolve_version.sh && mq_resolve "${MQ_VERSION:-}"
#   scripts/mq_resolve_version.sh 10.0   # prints the image tag
set -euo pipefail

MQ_VERSIONS_FILE="${MQ_VERSIONS_FILE:-mq-versions.json}"

mq_resolve() {
  command -v jq >/dev/null 2>&1 || {
    echo "mq_resolve_version: jq is required but not installed." \
         "Install jq: https://jqlang.github.io/jq/" >&2
    return 1
  }

  local alias="${1:-}"
  if [ -z "$alias" ]; then
    alias="$(jq -r '.default' "$MQ_VERSIONS_FILE")"
  fi

  local image
  if ! image="$(jq -er --arg v "$alias" '.versions[$v].image' "$MQ_VERSIONS_FILE" 2>/dev/null)"; then
    local known
    known="$(jq -r '.versions | keys | join(", ")' "$MQ_VERSIONS_FILE")"
    echo "mq_resolve_version: unknown MQ version '$alias'. Valid versions: $known." >&2
    return 1
  fi

  MQ_VERSION="$alias"
  MQ_IMAGE="$image"
  MQ_CAPS="$(jq -c --arg v "$alias" '.versions[$v].caps // []' "$MQ_VERSIONS_FILE")"
  COMPOSE_PROJECT_NAME="${MQ_PROJECT_NAME_PREFIX:-mq-dev}-${alias//./_}"
  export MQ_VERSION MQ_IMAGE MQ_CAPS COMPOSE_PROJECT_NAME
}

# Executed directly (not sourced): print the resolved image and exit.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  mq_resolve "${1:-}"
  echo "$MQ_IMAGE"
fi
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_resolve_version.sh`
Expected: PASS — every check `ok`, final line `PASS`.

- [ ] **Step 6: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: clean (shellcheck passes; the `SC1090` source is annotated).

- [ ] **Step 7: Commit**

```bash
vrg-git add scripts/mq_resolve_version.sh tests/fixtures/mq-versions.json tests/test_resolve_version.sh
vrg-commit --type feat --scope scripts --message "add version-resolve helper" --body "$(printf 'Resolves an MQ version alias to its image tag, capability list, and a\nper-version Compose project name. Sourced by the lifecycle scripts;\nfails loudly on an unknown alias and on missing jq.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 3: Matrix-list helper

**Files:**
- Create: `scripts/mq_versions_matrix.sh`
- Test: `tests/test_versions_matrix.sh`

**Interfaces:**
- Consumes: manifest at `$MQ_VERSIONS_FILE` (default `mq-versions.json`).
- Produces: prints a compact JSON array of version aliases (sorted by
  `jq keys`) to stdout, e.g. `["10.0","9.4.5"]`. Consumed by the reusable
  workflow in Task 6.

- [ ] **Step 1: Write the failing test**

Create `tests/test_versions_matrix.sh`:

```bash
#!/usr/bin/env bash
# Covers scripts/mq_versions_matrix.sh against the fixture manifest.
set -uo pipefail

export MQ_VERSIONS_FILE="tests/fixtures/mq-versions.json"
out="$(bash scripts/mq_versions_matrix.sh)"
if [ "$out" = '["10.0","9.4.5"]' ]; then
  echo "ok   - emits sorted JSON array of aliases"; echo "PASS"
else
  echo "FAIL - expected [\"10.0\",\"9.4.5\"] got [$out]"; exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_versions_matrix.sh`
Expected: FAIL — `scripts/mq_versions_matrix.sh` does not exist.

- [ ] **Step 3: Write the helper**

Create `scripts/mq_versions_matrix.sh`:

```bash
#!/usr/bin/env bash
# Print the manifest's version aliases as a compact JSON array, for use
# as a GitHub Actions matrix (consumed via fromJSON).
set -euo pipefail

MQ_VERSIONS_FILE="${MQ_VERSIONS_FILE:-mq-versions.json}"
jq -c '.versions | keys' "$MQ_VERSIONS_FILE"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_versions_matrix.sh`
Expected: PASS.

- [ ] **Step 5: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
vrg-git add scripts/mq_versions_matrix.sh tests/test_versions_matrix.sh
vrg-commit --type feat --scope scripts --message "add matrix-list helper" --body "$(printf 'Emits the manifest version aliases as a compact JSON array for the\nreusable workflow to feed a GitHub Actions matrix via fromJSON.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 4: Wire lifecycle scripts to the resolve helper

**Files:**
- Modify: `scripts/mq_start.sh`, `scripts/mq_stop.sh`,
  `scripts/mq_reset.sh`, `scripts/mq_seed.sh`, `scripts/mq_verify.sh`
- Test: `tests/test_lifecycle_wiring.sh`

**Interfaces:**
- Consumes: `mq_resolve` from Task 2.
- Produces: each lifecycle script, before any `docker compose` call,
  sources the helper and resolves `${MQ_VERSION:-}` so `MQ_IMAGE` and
  `COMPOSE_PROJECT_NAME` are exported for Compose.

**Note on test scope:** `mq_stop.sh` is the cleanest end-to-end probe of
the source→resolve→export→Compose chain because it has no readiness gate
or curl. The test stubs `docker` to capture `COMPOSE_PROJECT_NAME`. The
other four scripts get the identical two-line wiring and are covered by
shellcheck (`vrg-validate`) plus this shared-helper test; full
start/seed/verify behavior is exercised by the existing container-based
flow, not unit tests.

- [ ] **Step 1: Write the failing test**

Create `tests/test_lifecycle_wiring.sh`:

```bash
#!/usr/bin/env bash
# Verifies a lifecycle script resolves the per-version Compose project
# name and passes it to docker. Stubs `docker` on PATH to capture env.
set -uo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake docker: record COMPOSE_PROJECT_NAME, then succeed.
mkdir -p "$tmp/bin"
{
  echo '#!/usr/bin/env bash'
  echo 'printf "%s" "${COMPOSE_PROJECT_NAME:-UNSET}" > "$CAPTURE_FILE"'
  echo 'exit 0'
} > "$tmp/bin/docker"
chmod +x "$tmp/bin/docker"

export CAPTURE_FILE="$tmp/project"
PATH="$tmp/bin:$PATH" MQ_VERSION=10.0 bash scripts/mq_stop.sh >/dev/null 2>&1

got="$(cat "$tmp/project" 2>/dev/null || echo MISSING)"
if [ "$got" = "mq-dev-10_0" ]; then
  echo "ok   - mq_stop.sh resolves per-version project name"; echo "PASS"
else
  echo "FAIL - expected mq-dev-10_0 got [$got]"; exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_lifecycle_wiring.sh`
Expected: FAIL — `mq_stop.sh` does not yet source the helper, so
`COMPOSE_PROJECT_NAME` is `UNSET` (not `mq-dev-10_0`).

- [ ] **Step 3: Wire `mq_stop.sh`**

Modify `scripts/mq_stop.sh` to:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve the selected MQ version so COMPOSE_PROJECT_NAME targets the
# right per-version environment.
# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

docker compose -f config/docker-compose.yml down
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_lifecycle_wiring.sh`
Expected: PASS.

- [ ] **Step 5: Wire the remaining four scripts**

Add the same two-line block (after `set -euo pipefail`, before the first
`docker compose` call) to each:

`scripts/mq_start.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

docker compose -f config/docker-compose.yml up -d

# Block until both queue managers serve requests reliably.  The
# readiness gate lives in mq_wait_ready.sh so seed/verify (and any
# standalone caller) inherit the same stability window.
scripts/mq_wait_ready.sh
```

`scripts/mq_reset.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

docker compose -f config/docker-compose.yml down -v
```

(`mq_reset.sh` currently contains only the `down -v` line, so the full
file after editing is exactly the four lines above plus the two-line
source/resolve block — nothing else to preserve.)

`scripts/mq_seed.sh` — add the block immediately after
`set -euo pipefail`, keeping the existing `mq_wait_ready.sh` call and
`runmqsc` lines unchanged:

```bash
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"

# Don't seed until both queue managers serve requests — seeding (and
# the verify/tests that follow) must not race container startup.
scripts/mq_wait_ready.sh

docker compose -f config/docker-compose.yml exec -T qm1 runmqsc QM1 < seed/base-qm1.mqsc || true
docker compose -f config/docker-compose.yml exec -T qm2 runmqsc QM2 < seed/base-qm2.mqsc || true
```

`scripts/mq_verify.sh` — add the block immediately after
`set -euo pipefail` (before the existing variable assignments), leaving
the rest of the script unchanged:

```bash
#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/mq_resolve_version.sh
source scripts/mq_resolve_version.sh
mq_resolve "${MQ_VERSION:-}"
```

- [ ] **Step 6: Re-run the wiring test and validate**

Run: `bash tests/test_lifecycle_wiring.sh`
Expected: PASS.

Run: `vrg-container-run -- vrg-validate`
Expected: clean (shellcheck resolves the `source=` directives).

- [ ] **Step 7: Commit**

```bash
vrg-git add scripts/mq_start.sh scripts/mq_stop.sh scripts/mq_reset.sh scripts/mq_seed.sh scripts/mq_verify.sh tests/test_lifecycle_wiring.sh
vrg-commit --type feat --scope scripts --message "select MQ version in lifecycle scripts" --body "$(printf 'Each lifecycle script sources the resolve helper so MQ_IMAGE and a\nper-version COMPOSE_PROJECT_NAME are set before Compose runs. Switching\nversions locally no longer boots one version onto another versions\npersistent /var/mqm volume.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 5: setup-mq action — version input and outputs

**Files:**
- Modify: `.github/actions/setup-mq/action.yml`

**Interfaces:**
- Consumes: `mq_resolve` from Task 2 (via a new resolve step).
- Produces: action input `mq-version` (default `''` → manifest default);
  outputs `mq-version`, `mq-image`, `mq-caps`. The existing
  `qm1-rest-url`/`qm2-rest-url` outputs and the port inputs are
  unchanged. The `project-name` input becomes the project-name *prefix*
  (`MQ_PROJECT_NAME_PREFIX`); the helper appends the version slug.

- [ ] **Step 1: Add the `mq-version` input**

Under `inputs:` in `.github/actions/setup-mq/action.yml`, add:

```yaml
  mq-version:
    description: MQ version alias from mq-versions.json (default: manifest default)
    required: false
    default: ''
```

- [ ] **Step 2: Add version/image/caps outputs**

Under `outputs:`, add (keeping the existing URL outputs):

```yaml
  mq-version:
    description: Resolved MQ version alias
    value: ${{ steps.resolve.outputs.mq-version }}
  mq-image:
    description: Resolved MQ container image tag
    value: ${{ steps.resolve.outputs.mq-image }}
  mq-caps:
    description: Capability tokens for the resolved version (JSON array)
    value: ${{ steps.resolve.outputs.mq-caps }}
```

- [ ] **Step 3: Add a resolve step as the first step**

As the first entry under `runs.steps:`:

```yaml
    - name: Resolve MQ version
      id: resolve
      shell: bash
      working-directory: ${{ github.action_path }}/../../..
      env:
        MQ_VERSION: ${{ inputs.mq-version }}
        MQ_PROJECT_NAME_PREFIX: ${{ inputs.project-name }}
      run: |
        # shellcheck source=scripts/mq_resolve_version.sh
        source scripts/mq_resolve_version.sh
        mq_resolve "${MQ_VERSION:-}"
        {
          echo "mq-version=$MQ_VERSION"
          echo "mq-image=$MQ_IMAGE"
          echo "mq-caps=$MQ_CAPS"
        } >> "$GITHUB_OUTPUT"
```

- [ ] **Step 4: Pass version + prefix to the lifecycle steps**

In each existing step (`Start MQ containers`, `Seed MQ objects`,
`Verify MQ environment`), replace the `COMPOSE_PROJECT_NAME` env line with
the version + prefix so the script's own `mq_resolve` computes the same
project name. Each step's `env:` becomes, for example (Start):

```yaml
      env:
        MQ_VERSION: ${{ inputs.mq-version }}
        MQ_PROJECT_NAME_PREFIX: ${{ inputs.project-name }}
        QM1_REST_PORT: ${{ inputs.qm1-rest-port }}
        QM2_REST_PORT: ${{ inputs.qm2-rest-port }}
        QM1_MQ_PORT: ${{ inputs.qm1-mq-port }}
        QM2_MQ_PORT: ${{ inputs.qm2-mq-port }}
```

Apply the analogous change (drop `COMPOSE_PROJECT_NAME`, add `MQ_VERSION`
and `MQ_PROJECT_NAME_PREFIX`) to the Seed and Verify steps, preserving
each step's existing port env lines.

- [ ] **Step 5: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: clean — `actionlint` passes on the updated action.

- [ ] **Step 6: Commit**

```bash
vrg-git add .github/actions/setup-mq/action.yml
vrg-commit --type feat --scope action --message "add mq-version input and version outputs to setup-mq" --body "$(printf 'The action resolves a version alias via the manifest, exposes\nmq-version/mq-image/mq-caps outputs for version-aware consumer tests,\nand treats project-name as a prefix the helper namespaces by version.\nPorts and REST URLs are unchanged.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 6: Reusable workflow emitting the version matrix

**Files:**
- Create: `.github/workflows/mq-versions.yml`

**Interfaces:**
- Consumes: `scripts/mq_versions_matrix.sh` (Task 3) and the manifest's
  `.default`.
- Produces: a reusable workflow with `workflow_call` outputs `versions`
  (JSON array) and `default` (alias). Consumed by downstream repos via
  `fromJSON(needs.<job>.outputs.versions)`.

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/mq-versions.yml`:

```yaml
name: MQ versions
# Reusable workflow: publishes the supported MQ version list (from
# mq-versions.json) so consuming repos can build a test matrix that
# stays in sync with this repo. Consume at the rolling vX.Y tag.

on:
  workflow_call:
    outputs:
      versions:
        description: JSON array of supported MQ version aliases
        value: ${{ jobs.versions.outputs.versions }}
      default:
        description: Default MQ version alias
        value: ${{ jobs.versions.outputs.default }}

permissions:
  contents: read

jobs:
  versions:
    runs-on: ubuntu-latest
    outputs:
      versions: ${{ steps.read.outputs.versions }}
      default: ${{ steps.read.outputs.default }}
    steps:
      - uses: actions/checkout@v4
      - name: Read manifest
        id: read
        shell: bash
        run: |
          {
            echo "versions=$(bash scripts/mq_versions_matrix.sh)"
            echo "default=$(jq -r '.default' mq-versions.json)"
          } >> "$GITHUB_OUTPUT"
```

- [ ] **Step 2: Sanity-check the emitted values locally**

Run: `bash scripts/mq_versions_matrix.sh && jq -r '.default' mq-versions.json`
Expected: `["10.0","9.4.5"]` then `9.4.5` — exactly what the workflow
writes to `$GITHUB_OUTPUT`.

- [ ] **Step 3: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: clean — `actionlint` passes.

- [ ] **Step 4: Commit**

```bash
vrg-git add .github/workflows/mq-versions.yml
vrg-commit --type feat --scope ci --message "add reusable mq-versions matrix workflow" --body "$(printf 'Publishes the supported MQ version list and default from\nmq-versions.json as workflow_call outputs, so consuming repos build a\nversion matrix that auto-syncs when this repo adds a version. Consume at\nthe rolling vX.Y tag.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 7: CI workflow to run the bash tests

**Files:**
- Create: `.github/workflows/shell-tests.yml`

**Interfaces:**
- Consumes: every `tests/*.sh`.
- Produces: a PR-triggered job that runs the tests. Kept separate from
  the vergil-managed `ci.yml` to avoid managed-config conflicts.

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/shell-tests.yml`:

```yaml
name: Shell tests

on:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run bash tests
        shell: bash
        run: |
          status=0
          for t in tests/*.sh; do
            echo "== $t =="
            bash "$t" || status=1
          done
          exit "$status"
```

- [ ] **Step 2: Mirror locally what CI will do**

Run: `for t in tests/*.sh; do echo "== $t =="; bash "$t" || exit 1; done`
Expected: every test prints `PASS`; loop exits 0.

- [ ] **Step 3: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: clean — `actionlint` and `yamllint` pass.

- [ ] **Step 4: Commit**

```bash
vrg-git add .github/workflows/shell-tests.yml
vrg-commit --type ci --scope tests --message "run bash tests on PRs" --body "$(printf 'Dedicated workflow that runs the tests/ bash scripts on pull requests,\nkept separate from the vergil-managed ci.yml.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 8: Documentation

**Files:**
- Modify: `CLAUDE.md`, `README.md`,
  `docs/site/docs/architecture/environment-contract.md`

**Interfaces:**
- Consumes: behavior delivered in Tasks 1–6.
- Produces: docs covering version selection, the `jq` prerequisite, the
  version signals, and the consumption ref. No code interface.

- [ ] **Step 1: Update `CLAUDE.md`**

In the "Environment Setup" list, add `jq` as a prerequisite:

```markdown
- **jq**: JSON processor used to read `mq-versions.json` for version
  selection (`brew install jq` / `apt-get install jq`)
```

In "Container Lifecycle", document version selection:

```markdown
Select the MQ version with `MQ_VERSION` (alias from `mq-versions.json`;
defaults to the manifest `default`). Each version uses its own Docker
volumes, so switching is non-destructive:

\`\`\`bash
MQ_VERSION=10.0 scripts/mq_start.sh    # run 10.0
MQ_VERSION=9.4.5 scripts/mq_start.sh   # run 9.4.5
\`\`\`
```

In the Environment Contract table, change the Docker image row to:

```markdown
| Docker image | Selected via `mq-versions.json` (`MQ_VERSION`); default `icr.io/ibm-messaging/mq:9.4.5.1-r1` |
```

- [ ] **Step 2: Update `README.md`**

Add a short "MQ version selection" subsection near the lifecycle/usage
content:

```markdown
### MQ version selection

`mq-versions.json` lists the supported MQ versions. Set `MQ_VERSION` to an
alias (e.g. `10.0`, `9.4.5`) for any lifecycle script; omit it to use the
manifest `default`. CI consumers call the reusable `mq-versions.yml`
workflow to build a matrix and pass `mq-version` to the `setup-mq` action;
track the rolling `vX.Y` tag so new versions are picked up automatically.
```

- [ ] **Step 3: Update the environment-contract doc**

In `docs/site/docs/architecture/environment-contract.md`, update the
Docker image entry to match Step 1 (selected via `mq-versions.json`,
default `9.4.5.1-r1`) and add a sentence that the version is selectable
while ports, queue-manager names, and users are invariant across
versions.

- [ ] **Step 4: Validate**

Run: `vrg-container-run -- vrg-validate`
Expected: clean — `markdownlint` passes.

- [ ] **Step 5: Commit**

```bash
vrg-git add CLAUDE.md README.md docs/site/docs/architecture/environment-contract.md
vrg-commit --type docs --scope env --message "document MQ version selection" --body "$(printf 'Document MQ_VERSION selection, the jq prerequisite, per-version volume\nisolation, the version signals, and the rolling vX.Y consumption tag.\nNote the contract (ports, QM names, users) is invariant across versions.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Final verification

- [ ] Run the whole test suite:
  `for t in tests/*.sh; do echo "== $t =="; bash "$t" || exit 1; done`
  — all `PASS`.
- [ ] `vrg-container-run -- vrg-validate` — clean.
- [ ] Optional live smoke (requires Docker):
  `MQ_VERSION=9.4.5 scripts/mq_start.sh && scripts/mq_seed.sh && scripts/mq_verify.sh && scripts/mq_stop.sh`
  then repeat with `MQ_VERSION=10.0` and confirm both come up on the same
  ports with separate volumes (`docker volume ls | grep mq-dev`).
- [ ] Push: `vrg-git push`. PR creation is gated to a human maintainer.

## Out of scope (do not implement here)

- Flipping the manifest `default` to `10.0` (gated on
  `mq-rest-admin-common#217`).
- The `mapping-data.json` / `SSLQS`/`SSLQSR` mapper fix (owned by
  `mq-rest-admin-common#217`; enumeration in `#219`).
- Consuming-repo adoption across the language fleet (separate per-repo
  specs).
- Per-version seed overlays (`seed/overlays/<alias>/`) — add only when a
  version needs version-specific objects.
- A `bats` test framework — possible future fleet-wide follow-up.
