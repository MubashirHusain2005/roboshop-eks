FROM maven:3.9.12-eclipse-temurin-11-alpine AS build

WORKDIR /app

COPY pom.xml .

RUN mvn dependency:go-offline

COPY src ./src

RUN mvn package

FROM eclipse-temurin:11-jre-alpine AS runtime

EXPOSE 8080

WORKDIR /app

ENV CART_ENDPOINT=cart:8080
ENV DB_HOST=mysql

COPY --from=build /app/target/shipping-1.0.jar shipping.jar

CMD ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "shipping.jar"]