FROM node:25-alpine3.22 AS build

WORKDIR /catalogue

COPY package.json .

RUN npm install

COPY server.js .

ENV INSTANA_AUTO_PROFILE true

FROM node:25-alpine3.22 AS runtime

WORKDIR /catalogue

COPY  --from=build /catalogue /catalogue

EXPOSE 8080

CMD ["node", "server.js"]