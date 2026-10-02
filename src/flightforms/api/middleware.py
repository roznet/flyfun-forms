"""ASGI middleware that keeps request data out of logs and memory.

Pure ASGI rather than ``BaseHTTPMiddleware`` so the body limit can wrap
``receive`` and the error handler sees exceptions before Starlette's
``ServerErrorMiddleware``, which would log them with their message.
"""

import json
import logging
import traceback

from fastapi import HTTPException

logger = logging.getLogger(__name__)

# Form requests are a few KB of JSON; this leaves ample headroom for large
# manifests while bounding what an unauthenticated client can make us buffer
# and parse (the body is read before auth runs). Caddy enforces the same cap.
MAX_BODY_BYTES = 1024 * 1024


async def _send_json(send, status: int, detail: str) -> None:
    body = json.dumps({"detail": detail}).encode()
    await send({
        "type": "http.response.start",
        "status": status,
        "headers": [
            (b"content-type", b"application/json"),
            (b"content-length", str(len(body)).encode()),
        ],
    })
    await send({"type": "http.response.body", "body": body})


class BodySizeLimitMiddleware:
    """Reject request bodies over ``max_bytes`` with 413.

    Checks Content-Length up front and also counts streamed (chunked) bodies,
    raising ``HTTPException(413)`` from ``receive`` once the limit is passed;
    FastAPI lets that through its body parsing unchanged.
    """

    def __init__(self, app, max_bytes: int = MAX_BODY_BYTES):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        for name, value in scope.get("headers", []):
            if name == b"content-length":
                try:
                    too_large = int(value) > self.max_bytes
                except ValueError:
                    too_large = False
                if too_large:
                    await _send_json(send, 413, "Request body too large")
                    return

        received = 0

        async def limited_receive():
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise HTTPException(status_code=413, detail="Request body too large")
            return message

        await self.app(scope, limited_receive, send)


class RedactedErrorMiddleware:
    """Turn unhandled exceptions into a bare 500, logging no exception message.

    Requests carry passport data, and exception messages routinely quote the
    value that failed (``strptime``, ``int()``, ``KeyError``...). We log the
    exception type, route and stack frames (file, line, code), never the
    message or locals, so a traceback cannot put PII in the server log.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        response_started = False

        async def tracking_send(message):
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, receive, tracking_send)
        except Exception as exc:
            logger.error(
                "Unhandled %s on %s %s\n%s",
                type(exc).__name__,
                scope.get("method"),
                scope.get("path"),
                "".join(traceback.format_tb(exc.__traceback__)),
            )
            if not response_started:
                await _send_json(send, 500, "Internal server error")
