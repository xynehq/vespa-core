# Vespa Core

Standalone Vespa deployment for Xyne projects. This repository contains all Vespa-related schemas, deployment scripts, and configuration that can be run independently from the main Xyne application.

## Overview

This is a standalone Vespa deployment running in isolation. Applications connect to Vespa via HTTP endpoints for document indexing and search operations.

## Directory Structure

```
vespa-core/
├── vespa/
│   ├── schemas/              # 14 Vespa schema definitions
│   │   ├── file.sd
│   │   ├── user.sd
│   │   ├── mail.sd
│   │   └── ...
│   ├── services.xml          # Vespa service configuration
│   ├── deploy.sh             # Deployment script (local)
│   ├── deploy-docker.sh      # Deployment script (Docker)
│   ├── deploy-pod.sh         # Deployment script (Kubernetes)
│   ├── reindex.sh            # Reindexing script
│   ├── replaceDIMS.ts        # Replace embedding dimensions
│   └── models/               # Embedding models (downloaded)
├── deployment/
│   ├── Dockerfile-vespa-gpu  # GPU-enabled Vespa image
│   └── vespa-deploy/         # Deployment container
├── monitoring/
│   ├── prometheus.yml        # Prometheus configuration
│   └── vespa-detailed-monitoring.json  # Grafana dashboard
├── docker-compose.yml        # Standalone Vespa deployment
├── init-vespa.sh            # Initialize Vespa data directories
└── README.md
```

## Schemas

This instance includes 14 schemas:

1. **file** - Drive files with embeddings
2. **user** - User profiles
3. **mail** - Email documents
4. **mail_attachment** - Email attachments
5. **event** - Calendar events
6. **chat_message** - Slack/Teams messages
7. **chat_container** - Slack channels/Teams
8. **chat_user** - Chat platform users
9. **chat_team** - Slack workspaces/Teams
10. **chat_attachment** - Chat attachments
11. **datasource** - Custom data sources
12. **datasource_file** - Data source files
13. **kb_items** - Knowledge base items
14. **user_query** - User search history

## Quick Start

### 1. Local Development

```bash
# Start Vespa
docker-compose up -d

# Wait for Vespa to be ready (30-60 seconds)
docker logs vespa -f

# Deploy schemas
cd vespa
./deploy-docker.sh

# Verify deployment
curl http://localhost:8080/status.html
curl http://localhost:8081/status.html
```

### 2. VPC Deployment (Recommended for Production)

```bash
# On your VPC server (e.g., 10.0.2.50)
git clone <vespa-core-repo>
cd vespa-core

# Set embedding model
export EMBEDDING_MODEL=bge-base-en-v1.5

# Start Vespa
docker-compose up -d

# Deploy schemas
cd vespa
./deploy-docker.sh
```

Applications connect via:
```typescript
const client = new VespaClient({
  feedEndpoint: 'http://localhost:8080',
  queryEndpoint: 'http://localhost:8081'
})
```

### 3. With Monitoring

```bash
# Start with Prometheus & Grafana
docker-compose --profile monitoring up -d

# Access Grafana: http://localhost:3002
# Import dashboard from monitoring/vespa-detailed-monitoring.json
```

## Deployment

### Environment Variables

```bash
# Required
EMBEDDING_MODEL=bge-base-en-v1.5  # or bge-small-en-v1.5, bge-large-en-v1.5

# Optional
VESPA_FEED_PORT=8080
VESPA_QUERY_PORT=8081
```

### Embedding Models

Choose one based on your needs:

| Model | Dimensions | Memory | Speed | Quality |
|-------|-----------|--------|-------|---------|
| bge-small-en-v1.5 | 384 | Low | Fast | Good |
| bge-base-en-v1.5 | 768 | Medium | Medium | Better |
| bge-large-en-v1.5 | 1024 | High | Slow | Best |

### Initial Deployment

```bash
cd vespa

# 1. Set your embedding model
export EMBEDDING_MODEL=bge-base-en-v1.5

# 2. Deploy schemas
./deploy-docker.sh

# This will:
# - Download embedding models from HuggingFace
# - Replace DIMS placeholder with correct dimensions
# - Deploy all schemas to Vespa
# - Validate deployment
```

### Redeployment (Schema Updates)

```bash
cd vespa

# Deploy updated schemas
./deploy-docker.sh

# Note: Vespa will automatically restart and reload schemas
```

## Client Usage

Connect to Vespa from your application:

```typescript
import { VespaClient } from '@xyne/vespa-ts'

const client = new VespaClient({
  feedEndpoint: 'http://localhost:8080',
  queryEndpoint: 'http://localhost:8081'
})

// Index documents
await client.feed({
  schema: 'file',
  id: 'doc-1',
  fields: {
    title: 'My Document',
    content: 'Document content here'
  }
})

// Search documents
const results = await client.search({
  schema: 'file',
  query: 'document content'
})
```

## Endpoints

| Endpoint | Port | Purpose | Used By |
|----------|------|---------|---------|
| Feed | 8080 | Document ingestion | Applications |
| Query | 8081 | Search queries | Applications |
| Admin | 19071 | Schema deployment | Deployment scripts |
| Metrics | 19092 | Prometheus metrics | Monitoring |

## Data Persistence

Data is stored in Docker volumes:

```bash
# List volumes
docker volume ls | grep vespa

# Backup data
docker run --rm -v vespa-core_vespa-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/vespa-backup.tar.gz -C /data .

# Restore data
docker run --rm -v vespa-core_vespa-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/vespa-backup.tar.gz -C /data
```

## Maintenance

### Health Check

```bash
# Check Vespa status
curl http://localhost:19071/state/v1/health

# Check containers
curl http://localhost:8080/status.html  # Feed
curl http://localhost:8081/status.html  # Query
```

### Logs

```bash
# View Vespa logs
docker logs vespa -f

# View specific component logs
docker exec vespa tail -f /opt/vespa/logs/vespa/vespa.log
```

### Reindexing

If you change schema field types or need to rebuild indexes:

```bash
cd vespa
./reindex.sh
```

## Networking

### Docker Network

Vespa runs on the `xyne` bridge network. To allow other Docker containers to access it:

```yaml
# In your application's docker-compose.yml
networks:
  xyne:
    external: true
```

### Production Deployment

For production deployment:

1. Deploy this stack on a dedicated server
2. Ensure firewall rules allow inbound traffic on ports 8080 (feed) and 8081 (query)
3. Applications connect via the server's IP address
4. Use TLS/SSL for production traffic (configure reverse proxy)

## Troubleshooting

### Deployment Fails

```bash
# Check container status
docker ps -a | grep vespa

# Check logs for errors
docker logs vespa | grep -i error

# Verify health
curl http://localhost:19071/state/v1/health
```

### Out of Memory

```bash
# Increase memory limit in docker-compose.yml
deploy:
  resources:
    limits:
      memory: 12G  # Increase from 6G
```

### Schema Deployment Timeout

```bash
# Increase wait time in deploy-docker.sh
vespa deploy --wait 1800  # 30 minutes instead of 960 seconds
```

### Cannot Connect from Application

```bash
# Check network connectivity
docker exec -it xyne-app ping vespa

# Check firewall rules (VPC)
telnet 10.0.2.50 8081

# Verify endpoints in application config
echo $VESPA_QUERY_URL
```

## Performance Tuning

### Memory Settings

Edit `docker-compose.yml`:

```yaml
environment:
  - VESPA_CONFIGSERVER_JVMARGS=-Xms2g -Xmx32g -XX:+UseG1GC
  - VESPA_CONFIGPROXY_JVMARGS=-Xms1g -Xmx16g -XX:+UseG1GC
```

### Thread Pool

Edit `vespa/services.xml`:

```xml
<config name="container.handler.threadpool">
  <maxthreads>16</maxthreads>  <!-- Increase based on CPU cores -->
</config>
```

## Development Workflow

### Starting Vespa

```bash
# Start Vespa container
docker compose -f docker-compose.dev.yml up -d

# Wait for Vespa to be ready
docker logs vespa -f

# Deploy schemas
cd vespa && ./deploy-docker.sh
```

### Making Schema Changes

```bash
# Edit schemas in vespa/schemas/
vim vespa/schemas/file.sd

# Redeploy
cd vespa && ./deploy-docker.sh
```

### Stopping Vespa

```bash
docker compose -f docker-compose.dev.yml down
```

## Contributing

When adding new schemas:

1. Add `.sd` file to `vespa/schemas/`
2. Update `vespa/services.xml` to include new schema
3. Update this README's schema list
4. Redeploy: `cd vespa && ./deploy-docker.sh`
