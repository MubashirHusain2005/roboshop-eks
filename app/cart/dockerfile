FROM node:25-alpine3.22 AS build

WORKDIR /cart

COPY package.json .

RUN npm install

COPY server.js .

ENV INSTANA_AUTO_PROFILE true

FROM node:25-alpine3.22 AS runtime

WORKDIR /cart

COPY  --from=build /cart /cart

EXPOSE 8080

CMD ["node", "server.js"]