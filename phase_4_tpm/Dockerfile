FROM python:3.9-slim

WORKDIR /app

# Install necessary tools for debugging
RUN apt-get update && apt-get install -y \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy the application
COPY mtls_demo.py .

# Create directory for SPIRE Agent socket mount point
RUN mkdir -p /tmp/spire-agent/public

# Create directory for spire-agent binary mount point
RUN mkdir -p /opt/spire/bin

# Command to run the app
CMD ["python3", "mtls_demo.py"]
