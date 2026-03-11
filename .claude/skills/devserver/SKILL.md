---
name: devserver
description: Start or restart the local dev server for the iOS simulator in a tmux session
disable-model-invocation: true
---

# Local dev server management

Manage the `flightforms` tmux session that runs the FastAPI backend with SSL so the iOS simulator can reach it at `https://localhost.ro-z.me:8443`.

## Step 1 — Determine the project root

Figure out the correct project root (`PROJECT_ROOT`):
- Use the current working directory
- If we are in a git worktree (no `src/` dir, or `.git` is a file not a directory), the working directory IS the project root for that worktree

## Step 2 — Resolve the venv

- If `$PROJECT_ROOT/venv/` exists, use it
- Otherwise check `$PROJECT_ROOT/../main/venv/` (worktree case sharing main's venv)
- If neither exists, tell the user and stop

Store the resolved path as `VENV_PATH`.

### Ensure editable install points to current directory

When using a shared venv (especially `../main/venv/`), the package is installed in editable mode and the path may point elsewhere.

1. Activate the venv and check where the package currently points:
   ```bash
   source $VENV_PATH/bin/activate
   pip show flightforms | grep Location
   ```
2. If the Location does **not** match `$PROJECT_ROOT`, re-install:
   ```bash
   pip install -e "$PROJECT_ROOT"
   ```
3. Tell the user that the editable install was re-pointed to the current directory.

## Step 3 — Check for .env file

- If `$PROJECT_ROOT/.env` exists, good — nothing to do
- If it does NOT exist, create a minimal dev `.env`:
  ```
  ENVIRONMENT=development
  JWT_SECRET=dev-secret-not-for-production
  ```
  Tell the user it was created. In dev mode, flyfun-common uses SQLite and creates a dev user automatically — no MySQL or OAuth credentials needed.

## Step 4 — Check for existing tmux session

Run: `tmux has-session -t flightforms 2>/dev/null`

If a session exists:
1. Check what directory it's running in: `tmux display-message -t flightforms -p '#{pane_current_path}'`
2. Compare that path to `$PROJECT_ROOT`
3. **If the directory matches**, check if non-Python files have changed since the server started. `uvicorn --reload` only watches `.py` files, so JSON mappings and XLSX templates require a manual restart.

   Get the server start time (the tmux session creation time):
   ```bash
   tmux display-message -t flightforms -p '#{session_created}'
   ```
   Then check if any mapping or template files are newer:
   ```bash
   find "$PROJECT_ROOT/src/flightforms/mappings" "$PROJECT_ROOT/src/flightforms/templates" \
     -type f \( -name "*.json" -o -name "*.xlsx" \) \
     -newer <(ls -la --time-style=+%s) 2>/dev/null
   ```
   Or more reliably, use `stat` to compare modification times of those files against the session creation timestamp.

   - **If no non-Python files changed**, tell the user:
     > Dev server already running at https://localhost.ro-z.me:8443 — attach with `tmux attach -t flightforms`
     Then stop (no restart needed).

   - **If JSON/XLSX files changed since the server started**, restart the server:
     ```bash
     tmux send-keys -t flightforms C-c
     sleep 1
     ```
     Then continue to Step 6 to start fresh in the existing session (skip creating a new tmux session — just send the uvicorn command to the existing pane).
     Tell the user: "Restarted dev server — JSON mappings/templates changed since last start."

4. **If the directory does NOT match** (e.g., switched worktrees), kill the session:
   ```
   tmux kill-session -t flightforms
   ```
   Then continue to Step 5 to create a fresh one.

## Step 5 — Verify SSL certificates

Check that the SSL certs exist:
```bash
ls /usr/local/etc/letsencrypt/live/ro-z.me/fullchain.pem
ls /usr/local/etc/letsencrypt/live/ro-z.me/privkey.pem
```

If either is missing, tell the user and stop.

Store paths:
- `SSL_CERT=/usr/local/etc/letsencrypt/live/ro-z.me/fullchain.pem`
- `SSL_KEY=/usr/local/etc/letsencrypt/live/ro-z.me/privkey.pem`

## Step 6 — Start the tmux session

Create a new tmux session running the backend:

```bash
# Create detached session
tmux new-session -d -s flightforms -c "$PROJECT_ROOT"

# Run uvicorn with SSL on port 8443 (what the iOS simulator expects)
tmux send-keys -t flightforms "ENVIRONMENT=development $VENV_PATH/bin/python -m uvicorn flightforms.api.app:create_app --factory --reload --host 0.0.0.0 --port 8443 --ssl-certfile $SSL_CERT --ssl-keyfile $SSL_KEY" Enter
```

## Step 7 — Report to user

Tell the user:
- Backend running at **https://localhost.ro-z.me:8443**
- API docs at **https://localhost.ro-z.me:8443/docs**
- Attach to tmux with: `tmux attach -t flightforms`
- `uvicorn --reload` watches for Python file changes automatically
- In dev mode, auth is bypassed and a dev user is created automatically
