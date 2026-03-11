FROM python:3.13-slim

# Non-root user (UID 2000 to match infra convention)
RUN groupadd -g 2000 app && useradd -u 2000 -g app -m app

WORKDIR /app

# Install app dependencies (copy pyproject first for layer caching)
COPY pyproject.toml .
RUN mkdir -p src/flightforms && \
    touch src/flightforms/__init__.py && \
    pip install --no-cache-dir -e . && \
    rm -rf src/flightforms

# Copy application source
COPY src/ src/

# Create data directory
RUN mkdir -p /app/data && chown app:app /app/data

ENV ENVIRONMENT=production
ENV DATA_DIR=/app/data
ENV TEMPLATES_DIR=/app/src/flightforms/templates
ENV MAPPINGS_DIR=/app/src/flightforms/mappings

EXPOSE 8030

USER app

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8030/health')"

CMD ["uvicorn", "flightforms.api.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8030"]
