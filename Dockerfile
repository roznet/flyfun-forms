FROM python:3.13-slim

RUN groupadd -g 2000 app && useradd -u 2000 -g app -m app

WORKDIR /app

COPY pyproject.toml .
RUN pip install --no-cache-dir -e . 2>/dev/null || pip install --no-cache-dir .

COPY src/ src/

ENV ENVIRONMENT=production
ENV DATA_DIR=/app/data
ENV TEMPLATES_DIR=/app/src/flightforms/templates
ENV MAPPINGS_DIR=/app/src/flightforms/mappings

EXPOSE 8030

USER app

HEALTHCHECK --interval=30s --timeout=5s CMD python -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8030/health')"

CMD ["python", "-m", "uvicorn", "flightforms.api.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8030"]
