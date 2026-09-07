FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

FROM eclipse-temurin:21-jre
WORKDIR /app
ADD https://dtdg.co/latest-java-tracer /app/dd-java-agent.jar
COPY --from=build /app/target/hotel-search-api.jar app.jar
ENV DD_LOGS_INJECTION=true
ENV DD_PROFILING_ENABLED=true
# Lets the OpenTelemetry API used in the controllers feed the Datadog tracer.
ENV DD_TRACE_OTEL_ENABLED=true
ENTRYPOINT ["java", "-javaagent:/app/dd-java-agent.jar", "-jar", "app.jar"]
