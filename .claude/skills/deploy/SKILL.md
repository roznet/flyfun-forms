---
name: deploy
description: Deploy the flightforms app to production on forms.flyfun.aero
disable-model-invocation: true
---

# Deploy flightforms to production

Use the SSH user and server IP for flyfun.aero deployment from user config.
The project directory on the server is `flyfun-forms`.

## Pre-flight checks

1. Ensure the working tree is clean (`git status`)
2. Ensure we are on the `main` branch
3. Show the commits that will be deployed: `git log --oneline origin/main..HEAD`
4. Ask the user to confirm before proceeding

## Deploy steps

1. Push to remote: `git push origin main`
2. SSH to the server and deploy:
   ```
   ssh <user>@<server> "cd flyfun-forms && git pull && docker compose up -d --build"
   ```
3. Wait a few seconds, then verify the health check:
   ```
   ssh <user>@<server> "docker inspect --format='{{.State.Health.Status}}' flightforms"
   ```
4. Also check the endpoint is responding:
   ```
   curl -s -o /dev/null -w '%{http_code}' https://forms.flyfun.aero/health
   ```

## If something goes wrong

- Check logs: `ssh <user>@<server> "docker logs --tail 50 flightforms"`
- The container runs on port 8030 internally
- Docker container runs as UID 2000 (`app` user) — data volume must be chowned to match
- `docker compose` (v2 syntax, NOT `docker-compose`)
- Templates and mappings are bind-mounted read-only from the repo
