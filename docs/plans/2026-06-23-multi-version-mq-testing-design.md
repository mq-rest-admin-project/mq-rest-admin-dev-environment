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
drop-in for the administrative REST API? The mechanism below makes that
question answerable by running the same suite against both versions.

## Decisions (resolved during brainstorming)

1. **Execution model: select one version per run.** One version runs at
   a time on the stable contract ports (QM1 9443, QM2 9444, QM1/QM2 MQ
   listeners 1414/1415, users `mqadmin`/`mqreader`). CI sweeps versions
   with a matrix that runs the whole suite once per version. No
   side-by-side topology.
2. **Source of truth: a manifest in this repo.** A single
   `mq-versions.yml` maps version aliases to image tags and capability
   tokens and names a `default`. Scripts, the action, and a reusable
   workflow all read it. Adding/retiring a version is a one-line edit
   here.
3. **Default version: `10.0`.** When no version is selected, the
   environment uses the manifest `default`, which is `10.0`.
4. **Version-aware tests: yes.** The environment exports the resolved
   version and a capability map so consuming-repo tests can assert
   version-specific behavior or skip where a capability is absent,
   instead of collapsing to a lowest-common-denominator suite.

## Architecture

The manifest is the single lever. Three touch-points read it; the
environment contract stays invariant across versions because only one
version runs at a time on the same ports.

```text
mq-versions.yml  (source of truth)
   |
   +-- scripts/        mq_resolve_version.sh -> MQ_IMAGE/MQ_VERSION/MQ_CAPS  (local dev)
   +-- setup-mq action mq-version input  -> resolved version/image/caps outputs (CI per matrix leg)
   +-- mq-versions.yml workflow  emits version list as matrix JSON (CI matrix source)
```

**Contract invariant.** Because exactly one version runs at a time on
the same ports / queue-manager names / users, the environment contract
documented in `CLAUDE.md` and `README.md` is byte-for-byte identical
across versions. Consumers point at the same REST URLs regardless of
version; the only thing that varies is an out-of-band version *signal*.

## Component 1 — the version manifest

New file `mq-versions.yml` (repo root):

```yaml
default: "10.0"
versions:
  "9.4.5":
    image: icr.io/ibm-messaging/mq:9.4.5.1-r1
    caps: []                       # baseline
  "10.0":
    image: icr.io/ibm-messaging/mq:10.0.0.0-r1
    caps: [gskit9, native-ha-irr, multi-cert-labels]
```

- **Aliases** are human-friendly (`9.4.5`, `10.0`); full image tags live
  in one column so they are easy to bump.
- **`caps`** are short, stable tokens for *testable* version
  differences. The list starts near-empty and grows only as we identify
  real, asserted differences (YAGNI). A cap token is added here once a
  consuming test actually keys off it.
- **`default`** names the alias used when no version is selected.

The exact `10.0.0.0-r1` tag is a placeholder to be confirmed against the
published IBM MQ for Developers container tags during implementation.

## Component 2 — local dev (lifecycle scripts)

A shared helper `scripts/mq_resolve_version.sh` performs the manifest
lookup so the lifecycle scripts do not each reimplement parsing. The
existing scripts (`mq_start.sh`, `mq_reset.sh`, `mq_seed.sh`,
`mq_verify.sh`, `mq_stop.sh`) source it.

Behavior:

- `MQ_VERSION=10.0 scripts/mq_start.sh` resolves the alias, exports
  `MQ_IMAGE` for the existing compose flow, and exports `MQ_VERSION` and
  `MQ_CAPS` into the environment so a locally-run test suite sees the
  same signal CI provides.
- No `MQ_VERSION` set → use the manifest `default` (`10.0`).
- **Unknown alias → hard fail**, printing the list of valid aliases. No
  silent fallback to default, which would mask typos and silently test
  the wrong version. (Consistent with the no-silent-failures policy.)

`docker-compose.yml` is unchanged: it already reads
`${MQ_IMAGE:-...}`. The scripts now set `MQ_IMAGE` from the manifest
rather than relying on the compose default.

## Component 3 — CI mechanism

A GitHub Actions matrix is evaluated before any checkout, so it cannot
read a file directly. Two pieces bridge that gap.

### 3a. Reusable workflow `mq-versions.yml`

A new reusable *workflow* (distinct from the manifest file of the same
base name; final filename to be disambiguated during implementation,
e.g. `.github/workflows/mq-versions.yml`). A single small job:

- checks out this repo,
- reads the manifest,
- emits outputs `versions` (JSON array of aliases, e.g.
  `["9.4.5","10.0"]`) and `default`.

Consumers add one `needs:`-able job and feed `fromJSON(...)` into their
own matrix:

```yaml
jobs:
  mq-versions:
    uses: mq-rest-admin-project/mq-rest-admin-dev-environment/.github/workflows/mq-versions.yml@v1
  integration:
    needs: mq-versions
    strategy:
      matrix:
        mq: ${{ fromJSON(needs.mq-versions.outputs.versions) }}
    steps:
      - uses: mq-rest-admin-project/mq-rest-admin-dev-environment/.github/actions/setup-mq@v1
        with:
          mq-version: ${{ matrix.mq }}
```

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

### Mechanism versioning

The workflow and action are consumed at a tag (`@v1`). Adding an MQ
version to the manifest is a **non-breaking** change for consumers:
their matrix simply grows on the next run with no consumer edit. That is
the payoff of centralizing the version set.

## Seed data across versions

- The shared seed (`seed/base-qm1.mqsc`, `seed/base-qm2.mqsc`) must apply
  cleanly on **every** version in the manifest. This is now an invariant
  of adding a version. `mq_seed.sh` already runs version-blind.
- **No per-version overlays yet** (YAGNI). If a future version needs
  version-specific objects, add an optional `seed/overlays/<alias>/`
  directory that `mq_seed.sh` layers on when present. Not designed now.
- `mq_verify.sh` becomes version-aware via `MQ_CAPS`: baseline objects
  are checked on all versions; capability-gated checks run only where the
  capability is present.

## Backward-compatibility verification

The two-version matrix is the safety net: the full suite runs against
9.4.5 and 10.0, so any divergence surfaces as a CI failure on one leg.

Two risks to probe deliberately, derived from the MQ 10.0 change
analysis:

1. **GSKit 9 / post-quantum TLS.** GSKit is upgraded to v9 in 10.0,
   bringing FIPS 203 ML-KEM support. Cipher-negotiation behavior on the
   HTTPS path to `mqweb` may change. Watch for handshake/cipher issues
   in the REST clients.
2. **Additive REST attributes.** New object attributes may appear in
   10.0 REST responses. Confirm strict deserializers tolerate unknown
   fields rather than erroring.

**Open action, not resolved by this spec:** verify these against the IBM
MQ administrative REST API changelog/docs (not just the features-by-
version table) before declaring 10.0 a drop-in. Stated separately
because the change analysis describes feature areas (HA/CRR, Kafka,
Console, containers) that are largely orthogonal to the admin REST API
and notes 10.0 LTS is mostly a repackaging of 9.4.x CD — but that is an
inference, not a confirmed read of the REST API changelog.

Reference: IBM MQ features-by-version table —
<https://www.ibm.com/docs/en/ibm-mq/10.0.x?topic=information-mq-features-by-version>

## Out of scope (named, not designed here)

1. **Consuming-repo adoption** across the five languages — one spec per
   repo, building on this mechanism.
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
  version-conditional assertions/skips.
- The shared seed applies cleanly on every manifest version.
