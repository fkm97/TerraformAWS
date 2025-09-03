# Uses Alpine with Java 17 JRE (tiny and fast to pull)
FROM eclipse-temurin:17-jre-alpine

# Optional hardening/env
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="$JAVA_HOME/bin:$PATH"
ENV JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75"

WORKDIR /app
COPY spring-petclinic-3.5.0-SNAPSHOT.jar /app/app.jar

# Spring Boot defaults to 8080
EXPOSE 8080

# Use env-file for DB creds at runtime (provided via user-data)
ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]
