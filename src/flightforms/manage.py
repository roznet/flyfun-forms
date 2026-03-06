"""Management commands: run via `python -m flightforms.manage <command>`."""

import argparse
import hashlib
import secrets
import sys

from flyfun_common.db.engine import SessionLocal, get_engine, init_shared_db
from flyfun_common.db.models import ApiTokenRow, UserRow

from .db.models import AppBase

TOKEN_PREFIX = "ff_"


def cmd_create_token(args):
    """Create an API token for a user (by email). Creates the user if needed."""
    init_shared_db()
    AppBase.metadata.create_all(get_engine())
    session = SessionLocal()

    try:
        user = session.query(UserRow).filter_by(email=args.email).first()
        if not user:
            import uuid
            user = UserRow(
                id=str(uuid.uuid4()),
                provider="api",
                provider_sub=f"api:{args.email}",
                email=args.email,
                display_name=args.name or args.email,
                approved=True,
            )
            session.add(user)
            session.flush()
            print(f"Created API user: {user.email} ({user.id})")
        else:
            print(f"Found user: {user.email} ({user.id})")

        # Generate token
        raw_token = TOKEN_PREFIX + secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(raw_token.encode()).hexdigest()

        row = ApiTokenRow(
            user_id=user.id,
            token_hash=token_hash,
            name=args.label or "CLI token",
        )
        session.add(row)
        session.commit()

        print(f"\nToken created. Save this — it won't be shown again:\n")
        print(f"  {raw_token}\n")
        print(f"Usage:")
        print(f"  export FLIGHTFORMS_API_KEY='{raw_token}'")
        print(f"  flightforms --api-key '{raw_token}' airports")
    finally:
        session.close()


def cmd_list_tokens(args):
    """List all API tokens (hashes only, not plaintext)."""
    init_shared_db()
    session = SessionLocal()
    try:
        tokens = session.query(ApiTokenRow).all()
        if not tokens:
            print("No API tokens found.")
            return
        for t in tokens:
            user = session.get(UserRow, t.user_id)
            email = user.email if user else "unknown"
            status = "revoked" if t.revoked else "active"
            print(f"  [{status}] {t.name} — user: {email} — hash: {t.token_hash[:12]}...")
    finally:
        session.close()


def main():
    parser = argparse.ArgumentParser(prog="python -m flightforms.manage")
    sub = parser.add_subparsers(dest="command")

    ct = sub.add_parser("create-token", help="Create an API token for CLI access")
    ct.add_argument("--email", required=True, help="User email")
    ct.add_argument("--name", help="Display name (for new users)")
    ct.add_argument("--label", help="Token label (default: 'CLI token')")
    ct.set_defaults(func=cmd_create_token)

    lt = sub.add_parser("list-tokens", help="List API tokens")
    lt.set_defaults(func=cmd_list_tokens)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
