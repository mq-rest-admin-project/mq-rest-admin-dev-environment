# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.5] - 2026-06-24

### Features

- multi-version MQ testing via mq-versions.json manifest (#158)

## [1.2.4] - 2026-06-23

### Bug fixes

- gate lifecycle on queue-manager stability window (#152) (#153)

## [1.2.3] - 2026-06-23

### Bug fixes

- pass boolean to ci-security reusable workflow inputs (#125)
- pin MQ image to 9.4.5.1-r1 (latest supported 9.x) (#148)

### CI

- use dev-docs container for docs CI (#95)
- migrate to ci-security.yml reusable workflow (standard-actions#268) (#114)
- migrate CI/CD workflows to standard-actions v1.5 (#118)

### Chores

- prepare release 1.2.1
- merge main into release/1.2.2
- prepare release 1.2.2
- bump version to 1.2.3
- use .markdownlintignore for lint exclusions (#190) (#84)
- install standard-tooling plugin via marketplace (#86)
- strip CLAUDE.md boilerplate now covered by plugin (#88)
- container-first validation — containerise lint.sh (#90)
- ban MEMORY.md usage in CLAUDE.md (#91)
- use st-docker-test instead of legacy docker-test wrapper (#93)
- migrate standard-actions refs from @develop to @v1.3 (#99)
- upgrade standard-actions from @v1.3 to @v1.4 (#100)
- bootstrap st-config.toml for cache-first docker workflow (#101)
- seed standard-tooling.toml (#103)
- bump standard-actions pins from v1.1 to v1.4 (#105)
- strip config sections from repository-standards.md (#107)
- remove stale include directives and add standards reference (#108)
- add memory management policy (#110)
- delete stale st-config.toml (#113)
- add yamllint config and fix mkdocs line length (#116)
- remove legacy scripts/dev/ validation wrappers (#120)
- remove unused trivy-image vendor scan workflow (#122) (#123)
- fleet-wide config and workflow cleanup (#124)
- shorten issue template header comments to fit yamllint line-length (#126)
- migrate to reusable publish/docs workflows (#127)
- adopt CI/CD workflow naming convention (#383) (#128)
- migrate to mq-rest-admin-project org and vergil tooling (#130)
- remove co-authors config (#132)
- add missing container-tag/container-suffix and fix stale standards doc (#138)
- add Claude Code hook guard, scrub legacy hooksPath refs (#141)
- refresh managed config to Vergil v2.0.76 (items 1/3/4/6/7) (#144)
- migrate to vergil v2.1 (#146)

### Features

- adopt git worktree convention for parallel AI agent development (#97)
- add label to version selector in site header (#139)

### Refactoring

- align PR and issue templates with standard-tooling (#129)

## [1.2.2] - 2026-03-02

### Bug fixes

- set LTPA cookie name declaratively in mqwebuser.xml (#80)

### Chores

- bump version to 1.2.2 (#77)
- update standard-actions refs from @develop to @v1.1 (#78)

## [1.2.1] - 2026-03-01

### Bug fixes

- set stable LTPA cookie name in MQ container setup (#74)

### Chores

- prepare release 1.2.0
- bump version to 1.2.1

## [1.2.0] - 2026-02-27

### Chores

- prepare release 1.1.2
- bump version to 1.1.3
- add actionlint to lint.sh and CI (#66)
- bump version to 1.2.0 (#68)

## [1.1.2] - 2026-02-27

### Chores

- prepare release 1.1.1
- bump version to 1.1.2
- add cliff-release-notes.toml and backfill release notes (#62)

## [1.1.1] - 2026-02-27

### Bug fixes

- fix CHANGELOG.md formatting for markdownlint compliance
- escape glob patterns in CHANGELOG.md for markdownlint
- update add-to-project action to v1.0.2 (#42)
- update consuming repos to language-specific library names (#45)

### Chores

- merge main into release/1.1.0
- prepare release 1.1.0
- bump version to 1.1.1
- sync standard-tooling v1.1.4 (#40)
- migrate to PATH-based standard-tooling consumption (#47)
- add MQ listener port inputs to setup-mq composite action (#53)

### Documentation

- add MkDocs site, docs deployment workflow, and update repository profile (#44)
- replace stale script references with st-* commands (#48)
- complete documentation site with onboarding, port allocation, and env var references (#55)
- add Releases nav section to documentation site (#57)

### Refactoring

- remove docs-only detection and add tier-1 validation scripts (#50)

## [1.1.0] - 2026-02-21

### CI

- auto-add issues to GitHub Project (#16)
- add CI workflow with docs-only detection and shellcheck (#22)

### Chores

- bootstrap sync-tooling and add commit/PR wrapper scripts (#20)
- sync shared tooling to v1.0.5 (#24)
- add .gitignore with __pycache__ exclusion (#26)
- sync managed scripts against standard-tooling v1.1.1 (#31)
- remove push trigger from CI workflow (#33)

### Documentation

- add full README and mark pymqrest migration complete
- update self-references after repository rename (#18)
- ban MEMORY.md usage in CLAUDE.md (#28)
- ban heredocs in shell commands (#29)

### Features

- add repository scaffolding and design decisions (#1)
- migrate Docker config and lifecycle scripts from pymqrest (#4)
- rename PYMQREST.* object prefix to DEV.* (#7)
- add setup-mq composite action for CI consumption (#9)
- parameterize docker-compose for per-project isolation (#12)
- add weekly Trivy container image scan
- add category prefixes to job names (#27)
- adopt validate_local.sh dispatch architecture (#30)
- add publish workflow for automated tagging and version bumps (#36)
