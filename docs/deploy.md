# Deploy

Production is one host, alastor. The infra repo (`modules/wit-calendar`) defines the host. This repo only builds the image and starts the swap.

## Flow

```mermaid
sequenceDiagram
  participant GH as GitHub Actions
  participant A as alastor
  participant S1 as active slot
  participant S2 as idle slot
  participant T as Traefik

  GH->>GH: CI green on main
  GH->>GH: skip when main has moved past this commit
  GH->>GH: build and push ghcr.io/witcodingclub/calendar-backend:<sha>
  GH->>A: ssh: sudo wit-calendar-deploy <image>
  A->>S2: pull image, rails db:prepare, start container
  loop until /up answers 200
    A->>S2: GET /up
  end
  T->>S2: health check passes, traffic goes to both slots
  A->>S1: docker stop (30 s grace)
  T->>S1: health check fails, traffic goes to S2 only
  GH->>T: GET https://calendar.witcc.dev/up (must be 200 with x-runtime)
```

## Rules that follow from this

- Two app versions run at the same time for a few seconds. A migration runs while the old code still serves, so it must be safe next to the old code. strong_migrations enforces this (see `CLAUDE.md`).
- A failed migration or a container that never answers `/up` fails the deploy. The old slot keeps serving. Fix the problem and merge again.
- Deploys run one at a time. When several PRs merge in a row, the runs for the older commits skip themselves, and the run for the newest commit deploys everything. If the newest commit's CI is red, nothing deploys until a green commit lands.
- A manual run (`gh workflow run Deploy`) deploys the current `main` and never skips.
- Two Solid Queue workers run during the swap. Solid Queue locks jobs and recurring tasks in the database, so no job runs twice.

## Checks after a deploy

- `gh run list --workflow Deploy --limit 3`
- On alastor: `systemctl status 'wit-calendar-web@*'` shows which slot is active.
- On alastor: `sudo docker ps --format '{{.Names}} {{.Image}}'` shows the running image.
