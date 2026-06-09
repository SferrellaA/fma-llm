# Combined Ghidra Headless + MCP Bridge Docker Image
#
# Merges the upstream ghidra-mcp headless server (Java REST API) with the
# Python MCP↔HTTP bridge into a single container, reducing the container
# count by one vs. the original two-service setup.
#
# Upstream: https://github.com/bethington/ghidra-mcp (v5.13.1)

# =============================================================================
# Stage 1: Builder - Download Ghidra and build the plugin
# =============================================================================
FROM eclipse-temurin:21-jdk AS builder

# Build arguments — keep in sync with upstream pom.xml
ARG GHIDRA_VERSION=12.1
ARG GHIDRA_DATE=20260513

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    maven \
    && rm -rf /var/lib/apt/lists/*

# Download Ghidra
WORKDIR /opt
RUN wget -q --no-check-certificate \
    "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip" \
    -O ghidra.zip || \
    wget -q --no-check-certificate \
    "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC.zip" \
    -O ghidra.zip

RUN unzip -q ghidra.zip && \
    rm ghidra.zip && \
    mv ghidra_* ghidra

# Set Ghidra environment
ENV GHIDRA_HOME=/opt/ghidra
ENV PATH="${GHIDRA_HOME}:${PATH}"

# Install Ghidra JARs to Maven local repository
RUN mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Generic/lib/Generic.jar \
        -DgroupId=ghidra -DartifactId=Generic -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/SoftwareModeling/lib/SoftwareModeling.jar \
        -DgroupId=ghidra -DartifactId=SoftwareModeling -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Project/lib/Project.jar \
        -DgroupId=ghidra -DartifactId=Project -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Docking/lib/Docking.jar \
        -DgroupId=ghidra -DartifactId=Docking -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Utility/lib/Utility.jar \
        -DgroupId=ghidra -DartifactId=Utility -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Gui/lib/Gui.jar \
        -DgroupId=ghidra -DartifactId=Gui -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/FileSystem/lib/FileSystem.jar \
        -DgroupId=ghidra -DartifactId=FileSystem -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Help/lib/Help.jar \
        -DgroupId=ghidra -DartifactId=Help -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Features/Base/lib/Base.jar \
        -DgroupId=ghidra -DartifactId=Base -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Features/Decompiler/lib/Decompiler.jar \
        -DgroupId=ghidra -DartifactId=Decompiler -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/DB/lib/DB.jar \
        -DgroupId=ghidra -DartifactId=DB -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Framework/Emulation/lib/Emulation.jar \
        -DgroupId=ghidra -DartifactId=Emulation -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Debug/Debugger-api/lib/Debugger-api.jar \
        -DgroupId=ghidra -DartifactId=Debugger-api -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Debug/Framework-TraceModeling/lib/Framework-TraceModeling.jar \
        -DgroupId=ghidra -DartifactId=Framework-TraceModeling -Dversion=${GHIDRA_VERSION} -Dpackaging=jar && \
    mvn -q install:install-file -Dfile=/opt/ghidra/Ghidra/Debug/Debugger-rmi-trace/lib/Debugger-rmi-trace.jar \
        -DgroupId=ghidra -DartifactId=Debugger-rmi-trace -Dversion=${GHIDRA_VERSION} -Dpackaging=jar

# Download ghidra-mcp source tarball (avoids needing git in builder)
ADD https://github.com/bethington/ghidra-mcp/archive/refs/tags/v5.13.1.tar.gz /tmp/ghidra-mcp.tar.gz
RUN mkdir -p /build && \
    tar -xzf /tmp/ghidra-mcp.tar.gz -C /build --strip-components=1 && \
    rm /tmp/ghidra-mcp.tar.gz

WORKDIR /build

# Build the plugin with headless profile (skip tests for Docker build)
RUN mvn clean package -P headless -DskipTests -q

# =============================================================================
# Stage 2: Runtime - Ghidra headless server + Python MCP bridge
# =============================================================================
# NOTE: must be a JDK (not JRE) — Ghidra's GhidraScript OSGi loader uses
# javax.tools.ToolProvider.getSystemJavaCompiler() to compile .java scripts on
# the fly. That returns null on a JRE, causing
# "AssertException: Can't find java compiler" when running any Java script.
FROM eclipse-temurin:21-jdk

# Install runtime dependencies + Python for the MCP bridge
RUN apt-get update && apt-get install -y \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Copy Ghidra from builder
COPY --from=builder /opt/ghidra /opt/ghidra

# Set environment variables
ENV GHIDRA_HOME=/opt/ghidra
ENV GHIDRA_MCP_PORT=8089
ENV JAVA_OPTS="-Xmx4g -XX:+UseG1GC"

# Create directories
RUN mkdir -p /app /data /projects

# Copy the built headless JAR
COPY --from=builder /build/target/GhidraMCP-*.jar /app/GhidraMCP.jar

# Set up Python virtualenv and install bridge dependencies
RUN python3 -m venv /app/venv && \
    /app/venv/bin/pip install -q --no-cache-dir 'mcp>=1.2.0,<2'

# Download the MCP bridge script and patch it to forward GHIDRA_MCP_AUTH_TOKEN
RUN curl -sL -o /app/bridge_mcp_ghidra.py \
        https://raw.githubusercontent.com/bethington/ghidra-mcp/v5.13.1/bridge_mcp_ghidra.py && \
    python3 << 'PYEOF'
import re
with open('/app/bridge_mcp_ghidra.py') as f:
    code = f.read()
code = code.replace(
    '    headers = {}',
    '    headers = {}\n    auth_token = os.environ.get("GHIDRA_MCP_AUTH_TOKEN")\n    if auth_token:\n        headers["Authorization"] = f"Bearer {auth_token}"'
)
with open('/app/bridge_mcp_ghidra.py', 'w') as f:
    f.write(code)
PYEOF

# Copy entrypoint script
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Expose both the REST API and the MCP Streamable HTTP port
#   8089 — Ghidra headless REST API (direct access for debugging)
#   8090 — MCP Streamable HTTP endpoint (what Open WebUI / clients connect to)
EXPOSE 8089 8090

# Volume for persistent data and projects
VOLUME ["/data", "/projects"]

# Health check — verify Ghidra REST API is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -f http://localhost:${GHIDRA_MCP_PORT}/check_connection || exit 1

# Set working directory
WORKDIR /app

# Entrypoint — starts Ghidra server in background, then the Python MCP bridge
ENTRYPOINT ["/app/entrypoint.sh"]
