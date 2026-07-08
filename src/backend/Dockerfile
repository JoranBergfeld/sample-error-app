# --- Build stage ---
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -q -e -B dependency:go-offline
COPY src ./src
RUN mvn -q -e -B clean package -DskipTests

# --- Runtime stage ---
FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app
ARG AI_AGENT_VERSION=3.6.2
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/${AI_AGENT_VERSION}/applicationinsights-agent-${AI_AGENT_VERSION}.jar /app/applicationinsights-agent.jar
COPY --from=build /workspace/target/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/applicationinsights-agent.jar"
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
