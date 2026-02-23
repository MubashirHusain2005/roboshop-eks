FROM python:3.14.2-alpine3.23 AS build

WORKDIR /loadgen

COPY requirements.txt .
RUN pip install  --no-cache-dir -r requirements.txt

COPY entrypoint.sh .

COPY robot-shop.py .

FROM python:3.14.2-alpine3.23 AS runtime

WORKDIR /loadgen

ENV HOST="http://localhost:8080/" \
    SILENT=0 \
    NUM_CLIENTS=1 \
    ERROR=0 \
    RUN_TIME=0

RUN adduser -D appuser

COPY --from=build /usr/local /usr/local
COPY --from=build /loadgen /loadgen

USER appuser

CMD ["./entrypoint.sh"]