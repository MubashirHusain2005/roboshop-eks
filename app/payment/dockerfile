FROM python:3.14.2-alpine3.23 AS build

WORKDIR /payment

RUN apk add --no-cache build-base linux-headers

COPY requirements.txt .

RUN pip install  --no-cache-dir -r requirements.txt

COPY *.py .

COPY payment.ini .

ENV INSTANA_SERVICE_NAME=payment


FROM python:3.14.2-alpine3.23 AS runtime

WORKDIR /payment


COPY --from=build /usr/local /usr/local
COPY --from=build /payment /payment


EXPOSE 8080

CMD ["uwsgi", "--ini", "payment.ini"]