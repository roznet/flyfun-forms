"""Every route commits its session before the response is sent.

flyfun-common's ``current_user_id`` resolves ``Depends(get_db, scope="function")``.
A bare ``Depends(get_db)`` here would commit only after the response had gone
out, and give the request a second session (which locks on SQLite against the
token's ``last_used_at`` write). See flyfun-common ``designs/db.md``.
"""

import os


def test_no_route_resolves_get_db_at_request_scope():
    os.environ.setdefault("ENVIRONMENT", "development")
    os.environ.setdefault("JWT_SECRET", "test-secret-key-for-pytest")
    from flightforms.api.app import create_app
    from flyfun_common.db import find_request_scoped_db
    from flyfun_common.db.deps import _iter_route_dependants

    app = create_app()
    assert len(list(_iter_route_dependants(app.routes))) > 20
    assert find_request_scoped_db(app) == []
