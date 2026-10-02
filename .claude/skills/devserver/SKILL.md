---
name: devserver
description: Start or restart the local dev server for the iOS simulator in a tmux session
disable-model-invocation: true
---

# Local dev server management

Manage the `flightforms` tmux session that runs the FastAPI backend with SSL so the iOS simulator can reach it at `https://localhost.ro-z.me:8443`.

## Step 1 — Determine the project root

`PROJECT_ROOT=$(git rev-parse --show-toplevel)` — the checkout (or worktree) you're in.

## Step 2 — Resolve the venv

Each checkout has its own `venv/` (see CLAUDE.md). **Never fall back to another
checkout's venv** (e.g. `../main/venv`): its editable install would point at that
checkout, and the server would silently run the wrong code.

- If `$PROJECT_ROOT/venv/` exists **and is a real directory of this checkout**, use it.
  If it is a symlink, or its interpreter lives outside the checkout
  (`$PROJECT_ROOT/venv/bin/python -c "import sys; print(sys.prefix)"` not under
  `$PROJECT_ROOT`), it is shared with another checkout: don't use it and don't
  `pip install` into it — tell the user, and create a real one as below once they
  agree to remove the link.
- Otherwise create it and tell the user:
  ```bash
  python3 -m venv "$PROJECT_ROOT/venv" && "$PROJECT_ROOT/venv/bin/pip" install -e "$PROJECT_ROOT"
  ```

Store the path as `VENV_PATH`.

### Ensure the editable install points here

```bash
$VENV_PATH/bin/pip show -f flightforms | grep -E "Editable project location|Location"
```

If the editable location is not `$PROJECT_ROOT` (e.g. the venv was copied or the
repo moved), re-run `$VENV_PATH/bin/pip install -e "$PROJECT_ROOT"` and tell the user.

## Step 3 — Check for .env file

- If `$PROJECT_ROOT/.env` exists, good — nothing to do
- If it does NOT exist, create a minimal dev `.env`:
  ```
  ENVIRONMENT=development
  JWT_SECRET=dev-secret-not-for-production
  ```
  Tell the user it was created. In dev mode, flyfun-common uses SQLite and creates a dev user automatically — no MySQL or OAuth credentials needed.

## Step 4 — Check for existing tmux session

Run: `tmux has-session -t flightforms 2>/dev/null`. There is one session for the
whole machine, because the iOS simulator expects port 8443.

If a session exists:
1. Check what directory it's running in: `tmux display-message -t flightforms -p '#{pane_current_path}'`
2. **If it is a different directory** (another checkout), kill it —
   `tmux kill-session -t flightforms` — tell the user which checkout it was serving,
   and continue to Step 5.
3. **If it matches `$PROJECT_ROOT`**, check whether mappings or templates changed
   since it started. `uvicorn --reload` only watches `.py` files, so JSON mappings and
   PDF/DOCX/XLSX templates need a restart. The session creation time is the server
   start time (a restart always recreates the session, below):
   ```bash
   created=$(tmux display-message -t flightforms -p '#{session_created}')
   ref=$(mktemp)
   touch -t "$(date -r "$created" +%Y%m%d%H%M.%S)" "$ref"
   find "$PROJECT_ROOT/src/flightforms/mappings" "$PROJECT_ROOT/src/flightforms/templates" \
     -type f -newer "$ref"
   ```
   - **Nothing listed** → tell the user:
     > Dev server already running at https://localhost.ro-z.me:8443 — attach with `tmux attach -t flightforms`

     Then stop (no restart needed).
   - **Files listed** → `tmux kill-session -t flightforms`, continue to Step 5, and
     tell the user: "Restarted dev server — mappings/templates changed since last
     start: <files>."

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
