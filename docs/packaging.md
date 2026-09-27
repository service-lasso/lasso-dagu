# Packaging

## Canonical reader guidance

Start with [docs/service-authoring/overview.md](https://github.com/service-lasso/service-lasso/blob/develop/docs/service-authoring/overview.md) and [docs/service-authoring/03-create-release-repo.md](https://github.com/service-lasso/service-lasso/blob/develop/docs/service-authoring/03-create-release-repo.md) and [docs/service-authoring/05-validate-release.md](https://github.com/service-lasso/service-lasso/blob/develop/docs/service-authoring/05-validate-release.md). This page retains Dagu-owned component/reference contracts. Managed/custom workflow separation and opt-in stale pruning remain required. Scheduling and action-input design contracts do not prove automatic runtime integration, installed acceptance or publication. Migration: [Dagu #23](https://github.com/service-lasso/lasso-dagu/issues/23), [Core #1419](https://github.com/service-lasso/service-lasso/issues/1419), reviewed source `c6d4a55cb9263e9ba73fe09dbe975ec40dbc837d`.

Reference packaging scripts:
- `scripts/package.ps1`
- `scripts/package.sh`

Current Dagu direction:
- package the pinned upstream Dagu binary and Service Lasso launcher into a release artifact under `dist/`
- include `service.json`, runtime wrapper, config, managed directory placeholders, and workflow examples
- use the produced artifact as the thing later consumed by the shared harness
- keep generated Dagu state, logs, and workflow edits out of the release artifact unless they are intentional fixtures/examples

## App Artifact Modes

Service repos publish installable service archives from their own releases.

Apps that consume Service Lasso can then produce two useful runtime artifact modes:
- `runtime` / bootstrap-download: the app ships `services/<service-id>/service.json`, and Service Lasso downloads the service archive from that manifest during install/acquire.
- `bundled`: the app package step has already run Service Lasso package/acquire behavior and stored the service archive under `services/<service-id>/.state/artifacts/<tag>/<assetName>` before the app artifact is published.

Bundled app artifacts should not need a first-run service archive download. The service manifest still remains the source of truth for release metadata; the bundled archive is the already-acquired payload that matches that manifest.
