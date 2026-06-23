# Multi-version MQ testing — design

- **Date:** 2026-06-23
- **Issue:** #157
- **Status:** Approved design; implementation plan to follow
- **Scope:** Mechanism in this repo only. Consuming-repo adoption is
  deferred to separate per-repo cycles.

## Problem

The dev environment is locked to a single IBM MQ version (9.4.5.1). MQ
10.0 LTS went GA on 2026-06-16. We want to make 10.0 the primary
development and integration-test target for the mq-rest-admin tree while
keeping 9.4.5 in the test matrix, and to add future 10.x CD releases
independently as they ship — without consuming repos hardcoding or
drifting on the version set.

A secondary driver is a backward-compatibility question: is 10.0 a
drop-in for the administrative REST API? This is **not hypothetical**.
The image previously floated on `…/mq:latest`, which rolled to MQ 10.0.0;
real 10.0 returned new quantum-safe `DISPLAY CHSTATUS` attributes
(`SSLQS`/`SSLQSR`) that the shared `mapping-data.json` did not map, so
every language repo's strict response mapper raised and the integration
CI gate failed. Commit `12717c1` (#148, 2026-06-23) pinned the image to
`9.4.5.1-r1` to escape that, and v10 enablement — including the
`SSLQS`/`SSLQSR` mappings — is tracked in `mq-rest-admin-common#217`.

So this work is not "discover whether 10.0 breaks the mapper." We
already know it does, in a specific way, today. This mechanism makes 10.0
a first-class, selectable test target so that fix (and future ones) can
be validated against both versions — and it must be sequenced behind the
mapping work, not ahead of it.

## Decisions (resolved during brainstorming)

1. **Execution model: select one version per run.** One version runs at
   a time on the stable contract ports (QM1 9443, QM2 9444, QM1/QM2 MQ
   listeners 1414/1415, users `mqadmin`/`mqreader`). CI sweeps versions
   with a matrix that runs the whole suite once per version. No
   side-by-side topology.
2. **Source of truth: a manifest in this repo.** A single
   `mq-versions.json` maps version aliases to image tags and capability
   tokens and names a `default`. JSON (not YAML) so bash scripts parse it
   with `jq` — one common dependency — and so the version list drops
   straight into a GitHub Actions matrix via `fromJSON` with no
   conversion. Scripts, the action, and a reusable workflow all read it.
   Adding/retiring a version is a one-line edit here.
3. **Default version: `10.0` is the end-state, gated on the mapper.**
   When no version is selected, the environment uses the manifest
   `default`. `10.0` is the intended default, but flipping it is what
   makes every default-only consumer start exercising 10.0, so it is
   sequenced behind the `mq-rest-admin-common#217` mapper fix (see
   Dependencies & sequencing). The manifest may ship with
   `default: "9.4.5"` until then.
4. **Version-aware tests: yes.** The environment exports the resolved
   version and a capability map so consuming-repo tests can assert
   version-specific behavior or skip where a capability is absent,
   instead of collapsing to a lowest-common-denominator suite.

## Architecture

The manifest is the single lever. Three touch-points read it; the
environment contract stays invariant across versions because only one
version runs at a time on the same ports.

```text
mq-versions.json  (source of truth, parsed with jq)
   |
   +-- scripts/        mq_resolve_version.sh -> MQ_IMAGE/MQ_VERSION/MQ_CAPS  (local dev)
   +-- setup-mq action mq-version input  -> resolved version/image/caps outputs (CI per matrix leg)
   +-- mq-versions workflow  emits version list as matrix JSON (CI matrix source)
```

**Contract invariant.** Because exactly one version runs at a time on
the same ports / queue-manager names / users, the environment contract
documented in `CLAUDE.md` and `README.md` is byte-for-byte identical
across versions. Consumers point at the same REST URLs regardless of
version; the only thing that varies is an out-of-band version *signal*.

**Boundary with the shared mapper.** The thing that actually broke on
10.0 is not in this repo: it is the strict response mapper driven by
`mapping-data.json`, which lives in `mq-rest-admin-common` and is shared
by all the language repos. This repo owns *which MQ version is running
and how to select it*; `mq-rest-admin-common` owns *how REST responses
from that version are mapped to fields*. The two must not both try to
own the attribute catalog (see Dependencies & sequencing). This repo's
version signal is the input that lets the mapper — and version-aware
tests — branch correctly; it is not itself the attribute map.

## Component 1 — the version manifest

New file `mq-versions.json` (repo root). JSON comments are not legal, so
the gating note lives in the spec/docs rather than the file:

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

`default` is `9.4.5` today and flips to `10.0` once
`mq-rest-admin-common#217` lands (see Dependencies & sequencing).
`chstatus-quantum-safe` marks that 10.0 emits `SSLQS`/`SSLQSR` on
`DISPLAY CHSTATUS`.

- **Aliases** are human-friendly (`9.4.5`, `10.0`); full image tags live
  in one column so they are easy to bump. `10.0.0.0-r1` is confirmed as
  the only 10.x multi-arch tag on icr.io (per #148), and `9.4.5.1-r1` is
  the highest 9.x multi-arch tag.
- **`caps`** are short, stable tokens for *coarse, environment-level*
  capabilities a test legitimately gates on at the environment level —
  e.g. "this version emits the quantum-safe CHSTATUS attributes." They
  are **not** a mirror of `mapping-data.json`. Fine-grained REST
  attribute-to-field mappings stay in `mq-rest-admin-common`, keyed by
  version, as the single source of truth; duplicating them here would
  create two catalogs that drift. The list starts minimal and grows only
  when a consuming test actually keys off a token (YAGNI).
- **`default`** names the alias used when no version is selected.

The first real token, `chstatus-quantum-safe`, names exactly the surface
that broke under #148: 10.0's new `SSLQS`/`SSLQSR` attributes on
`DISPLAY CHSTATUS`. It exists so a test can assert presence on 10.0 and
absence on 9.4.5 without re-encoding the field mappings that
`mq-rest-admin-common#217` owns.

## Component 2 — local dev (lifecycle scripts)

A shared helper `scripts/mq_resolve_version.sh` performs the manifest
lookup (via `jq`) so the lifecycle scripts do not each reimplement
parsing. The existing scripts (`mq_start.sh`, `mq_reset.sh`,
`mq_seed.sh`, `mq_verify.sh`, `mq_stop.sh`) source it. **`jq` becomes a
declared local prerequisite** (alongside Docker and curl in CLAUDE.md);
the helper fails loudly with an install hint if `jq` is absent rather
than silently degrading.

Behavior:

- `MQ_VERSION=10.0 scripts/mq_start.sh` resolves the alias, exports
  `MQ_IMAGE` for the existing compose flow, and exports `MQ_VERSION` and
  `MQ_CAPS` into the environment so a locally-run test suite sees the
  same signal CI provides.
- No `MQ_VERSION` set → use the manifest `default` (currently `9.4.5`;
  `10.0` once #217 lands).
- **Unknown alias → hard fail**, printing the list of valid aliases. No
  silent fallback to default, which would mask typos and silently test
  the wrong version. (Consistent with the no-silent-failures policy.)

`docker-compose.yml` is unchanged: it already reads
`${MQ_IMAGE:-...}`. The scripts now set `MQ_IMAGE` from the manifest
rather than relying on the compose default.

### Per-version data isolation (volume lifecycle)

The compose file mounts named volumes (`qm1data`, `qm2data`) that persist
across `mq_stop.sh` (it runs `down`, not `down -v`). Because MQ
queue-manager data migration is one-way, booting one version on another
version's `/var/mqm` fails or corrupts. With "select one per run", a
local developer *will* switch versions, so the data must be isolated per
version.

**Mechanism:** the resolve helper sets `COMPOSE_PROJECT_NAME` to include
the version alias (e.g. `mq-dev-10_0`, `mq-dev-9_4_5`; dots normalized to
underscores for Docker's naming rules). Docker prefixes volume and
container names with the project name, so each version gets its own
isolated `/var/mqm`. Switching versions is then **non-destructive** — the
9.4.5 data survives while you exercise 10.0, and vice versa.

Consequences threaded through the scripts:

- `mq_stop.sh` / `mq_reset.sh` operate on the **same** project name the
  resolve helper computes for the selected version, so they stop and
  (for reset) wipe the right environment rather than a default-named one.
- This reuses the isolation the `setup-mq` action already exposes via its
  `project-name` input; in CI each matrix leg additionally runs on a
  fresh runner, so cross-version contamination cannot occur there.
- Disk cost: one `/var/mqm` pair per version the developer has started.
  `mq_reset.sh` (now project-scoped) reclaims a version's volumes.

## Component 3 — CI mechanism

A GitHub Actions matrix is evaluated before any checkout, so it cannot
read a file directly. Two pieces bridge that gap.

### 3a. Reusable workflow `.github/workflows/mq-versions.yml`

A new reusable *workflow*. The manifest is now `mq-versions.json`, so the
old name collision with the manifest is gone; the workflow keeps the
descriptive `mq-versions.yml` filename. A single small job:

- checks out this repo,
- reads `mq-versions.json` with `jq` (present on GitHub-hosted runners),
- emits outputs `versions` (JSON array of aliases, e.g.
  `["9.4.5","10.0"]`, via `jq -c '.versions | keys'`) and `default`.

Consumers add one `needs:`-able job and feed `fromJSON(...)` into their
own matrix:

```yaml
jobs:
  mq-versions:
    uses: mq-rest-admin-project/mq-rest-admin-dev-environment/.github/workflows/mq-versions.yml@vX.Y
  integration:
    needs: mq-versions
    strategy:
      matrix:
        mq: ${{ fromJSON(needs.mq-versions.outputs.versions) }}
    steps:
      - uses: mq-rest-admin-project/mq-rest-admin-dev-environment/.github/actions/setup-mq@vX.Y
        with:
          mq-version: ${{ matrix.mq }}
```

`@vX.Y` is the **rolling major-minor tag** — the standard, recommended
consumption ref for both the workflow and the action. It moves forward
within a minor series, so consumers stay current without editing the ref
(see Mechanism versioning). Consumers substitute the current series
(e.g. `@v1.2`).

Consumers keep control of their own test command and may subset the
sweep (for example `default`-only on draft PRs, full sweep on main) —
they simply never hardcode the version list.

### 3b. `setup-mq` action additions

- **New input:** `mq-version` (alias; defaults to the manifest
  `default`).
- **New outputs:** `mq-version` (resolved), `mq-image` (resolved tag),
  `mq-caps` (JSON).
- **Unchanged outputs:** `qm1-rest-url`, `qm2-rest-url` — the ports are
  stable, so these do not vary by version.

The action resolves the alias via the same manifest the scripts use.

### Mechanism versioning & consumption-ref contract

**Standard consumption ref: the rolling major-minor tag `vX.Y`.** This
repo already publishes moving minor tags (`v1.1`, `v1.2`) and immutable
patch tags (`v1.2.4`); the agreed convention is that consumers track the
rolling `vX.Y` tag for both the reusable workflow and the action. (No
bare `v1` major tag is used.)

The workflow and action are new capabilities, so consumers reference the
`vX.Y` series at or after the release that introduces them.

The headline benefit — *add a version to the manifest and every
consumer's matrix grows on the next run, with no consumer edit* — follows
directly from tracking the rolling tag: a new MQ version ships in a patch
release on the same `vX.Y` series, and consumers pick it up automatically.
A consumer that instead pins an immutable patch tag (`@v1.2.4`) is frozen
at that manifest snapshot — supported, but it opts out of auto-sync.

Adding an MQ version is a **non-breaking** change to the manifest (patch
bump on the current `vX.Y`); removing or renaming an alias, or changing
an action input/output, is breaking and rides a minor/major bump — which,
by definition, moves consumers to a new `vX.Y` series deliberately.

## Seed data across versions

- The shared seed (`seed/base-qm1.mqsc`, `seed/base-qm2.mqsc`) must apply
  cleanly on **every** version in the manifest. This is now an invariant
  of adding a version. `mq_seed.sh` already runs version-blind.
- **No per-version overlays yet** (YAGNI). If a future version needs
  version-specific objects, add an optional `seed/overlays/<alias>/`
  directory that `mq_seed.sh` layers on when present. Not designed now.
- `mq_verify.sh` checks the baseline **seed objects** on every version
  (version-blind — seed objects are the same across versions). Separately
  and optionally, it may use `MQ_CAPS` to assert version-specific
  **REST-attribute** behavior (e.g. `SSLQS`/`SSLQSR` present on 10.0).
  These are two distinct axes — seed-object presence vs version attribute
  surface — and the spec keeps them separate rather than gating seed
  checks on caps.

## Backward-compatibility status

The two-version matrix is the safety net: the full suite runs against
9.4.5 and 10.0, so any divergence surfaces as a CI failure on one leg.
But the headline divergence is already known, not something the matrix
will "discover":

1. **Additive REST attributes — CONFIRMED, already broke (#148).** 10.0
   emits `SSLQS`/`SSLQSR` on `DISPLAY CHSTATUS`; the strict mapper in
   `mq-rest-admin-common` raised on the unmapped attributes and the
   integration gate failed. The fix is the `mapping-data.json` update
   tracked in `mq-rest-admin-common#217`. **Until that lands, a 10.0
   matrix leg against the current fleet will red-light by construction.**
   This spec therefore sequences the 10.0 leg behind #217 (see
   Dependencies & sequencing) rather than pretending the matrix is green
   on day one.
2. **GSKit 9 / post-quantum TLS — to probe.** GSKit is upgraded to v9 in
   10.0 (FIPS 203 ML-KEM). Cipher-negotiation on the HTTPS path to
   `mqweb` may change; watch for handshake issues in the REST clients.
   This one is genuinely unverified, unlike (1).

**Open action, not resolved by this spec:** beyond `SSLQS`/`SSLQSR`,
check the IBM admin REST API changelog for *other* additive 10.0
attributes the mapper will need, so #217 is scoped completely rather than
fixing only the attributes that happened to surface first. The MQ 10.0
change analysis describes feature areas (HA/CRR, Kafka, Console,
containers) largely orthogonal to the admin REST API, but that is an
inference, not a confirmed read of the changelog.

Reference: IBM MQ features-by-version table —
<https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=information-mq-features-by-version>

## Dependencies & sequencing

This mechanism touches two repos and must land in order:

1. **`mq-rest-admin-common#217` (v10 mapper enablement)** — adds the
   `SSLQS`/`SSLQSR` (and any other missing 10.0) mappings to
   `mapping-data.json`. This is the prerequisite: without it, 10.0 fails
   the mapper regardless of how good the environment mechanism is.
2. **This repo (the environment mechanism)** — manifest, scripts, action,
   reusable workflow. Can be *built* in parallel with #217, but the
   `default` should not flip to `10.0` for the fleet, and consumers
   should not add a non-allow-failure 10.0 matrix leg, until #217 has
   landed and the mappers accept 10.0 responses.
3. **Consuming-repo adoption** (separate cycle, per repo) — wires the
   reusable workflow + action into each language repo's CI and adds any
   version-conditional tests.

**Coordination note on `default: "10.0"`.** The manifest defaulting to
10.0 is the agreed end-state, but flipping it is the step that makes
every default-only consumer start exercising 10.0. Treat the default
flip as a deliberate switch gated on #217, not as something that ships
silently with the mechanism. Until then the manifest ships with
`default: "9.4.5"`. Since `mq-versions.json` cannot carry comments, the
intended end-state (10.0 once the mapper lands) is recorded here and in
the repo docs rather than inline; flipping `default` to `10.0` is a
one-line follow-up gated on #217.

Related history/tracking: #147 (origin of the pin), #148 (the pin
itself), `mq-rest-admin-common#217` (mapper enablement).

## Out of scope (named, not designed here)

1. **Consuming-repo adoption** across the language repos / fleet — one
   spec per repo, building on this mechanism. (The repo docs currently
   name `pymqrest`, `mq-rest-admin`, and planned `pymqpcf`; #148 refers
   to "every language repo" and `mq-rest-admin-common`, so the actual
   fleet is larger — adoption specs should enumerate it explicitly.)
2. **The `mapping-data.json` / mapper fix itself** — owned by
   `mq-rest-admin-common#217`, not this repo. This spec depends on it but
   does not design it.
2. **Version-lifecycle policy** — how long to keep 9.4.x, when to add
   10.x CD releases. Editorial; lives in docs and is driven by manifest
   edits.
3. **Contract documentation** — updating the environment-contract table
   in `CLAUDE.md` / `README.md` to document version selection and the new
   version signals. (Done as part of implementation, but the policy/
   wording is editorial.)

## Success criteria

- A developer can run `MQ_VERSION=9.4.5 scripts/mq_start.sh` or
  `MQ_VERSION=10.0 scripts/mq_start.sh` (or omit it for the default) and
  get a working environment on the stable ports.
- Unknown `MQ_VERSION` fails loudly with the valid alias list.
- A consuming repo can call the reusable workflow + `setup-mq` action and
  get its integration suite run once per manifest version, with no
  hardcoded version list.
- Tests can read the resolved version and capabilities to make
  version-conditional assertions/skips (e.g. assert `SSLQS`/`SSLQSR`
  present on 10.0, absent on 9.4.5).
- The shared seed applies cleanly on every manifest version.
- **Once `mq-rest-admin-common#217` has landed**, the 10.0 matrix leg
  passes against the fleet and the manifest `default` can be flipped to
  `10.0`. Before that, the mechanism is complete but 10.0 runs as an
  allow-failure / non-default leg — it does not gate merges on a failure
  that is expected until the mapper is fixed.
