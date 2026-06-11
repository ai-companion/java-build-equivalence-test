FROM docker.io/library/eclipse-temurin:8-jdk-jammy

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip python3 diffutils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Download comparison tools
RUN mkdir -p /workspace/tools && \
    curl -fsSL -o /workspace/tools/japicmp.jar \
        https://repo1.maven.org/maven2/com/github/siom79/japicmp/japicmp/0.23.0/japicmp-0.23.0-jar-with-dependencies.jar && \
    curl -fsSL -o /workspace/tools/cfr.jar \
        https://repo1.maven.org/maven2/org/benf/cfr/0.152/cfr-0.152.jar

COPY tools/run-all.sh /workspace/tools/run-all.sh
RUN chmod +x /workspace/tools/run-all.sh
