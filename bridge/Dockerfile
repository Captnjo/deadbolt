FROM python:3.12-slim

WORKDIR /app

COPY pyproject.toml .
COPY bridge/ bridge/

RUN pip install --no-cache-dir .

EXPOSE 9877

ENTRYPOINT ["deadbolt-bridge"]
CMD ["--host", "0.0.0.0", "--port", "9877"]
