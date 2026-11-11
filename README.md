# Knowledge Base System

A **Living Knowledge System** implementing Hybrid RAG architecture for organization-specific LLM chat applications.

## Features

- **Hybrid Knowledge**: Blends internal documents with web-harvested content
- **Model Agnostic**: LiteLLM gateway supports multiple LLM providers
- **HITL Review**: Human-in-the-loop approval for web-harvested content
- **Real-time Chat**: SSE streaming responses with source attribution
- **AWS-Ready**: Designed for AWS Bedrock with VPC isolation

## Architecture

```
┌────────────┐   ┌────────────┐   ┌────────────┐
│  Chat UI   │   │ Review UI  │   │  Admin UI  │
└─────┬──────┘   └─────┬──────┘   └─────┬──────┘
      │                │                │
      └────────┬───────┴────────┬───────┘
               │                │
         ┌─────▼────────────────▼─────┐
         │      FastAPI Backend       │
         │  (Chat, Documents, Review) │
         └─────┬────────────────┬─────┘
               │                │
    ┌──────────▼──┐      ┌──────▼──────┐
    │   Qdrant    │      │  PostgreSQL │
    │ (Vectors)   │      │ (Metadata)  │
    └─────────────┘      └─────────────┘
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| LLM | Claude 3.5 Sonnet via AWS Bedrock |
| Gateway | LiteLLM |
| Embeddings | Cohere embed-v4 |
| Vector DB | Qdrant |
| Backend | FastAPI (Python 3.11+) |
| Frontend | Next.js 14 |
| Orchestration | LangGraph |

## Quick Start

```bash
# 1. Setup environment
cp .env.example .env
# Edit .env with your API keys

# 2. Start infrastructure
docker-compose up -d

# 3. Install backend
cd backend && pip install -e ".[dev]"

# 4. Run migrations
alembic upgrade head

# 5. Start API
uvicorn src.main:app --reload

# Access API docs: http://localhost:8000/docs
```

## Implementation Status

| Phase | Status | Description |
|-------|--------|-------------|
| 1. Foundation | ✅ Complete | Project setup, Docker, config |
| 2. Embeddings | ✅ Complete | Cohere + Qdrant integration |
| 3. Ingestion | ✅ Complete | Document upload & processing |
| 4. Chat API | ✅ Complete | RAG with streaming responses |
| 5. Harvester | 🔲 Pending | Web scraping with LangGraph |
| 6. Review UI | 🔲 Pending | HITL approval dashboard |
| 7. Chat UI | 🔲 Pending | Next.js chat interface |
| 8. Admin | 🔲 Pending | Admin UI & audit logs |

**See [IMPLEMENTATION_STATUS.md](./IMPLEMENTATION_STATUS.md) for detailed progress and next steps.**

## API Endpoints

```
# Chat
POST /api/v1/chat/completions    # Streaming chat with RAG

# Documents
POST /api/v1/documents/upload    # Upload document
GET  /api/v1/documents           # List documents
DELETE /api/v1/documents/{id}    # Delete document

# Health
GET  /health                     # Health check
GET  /ready                      # Readiness check
```

## Project Structure

```
knowledge-base-system/
├── backend/                 # FastAPI backend
│   ├── src/
│   │   ├── api/v1/         # REST endpoints
│   │   ├── core/           # LLM, embeddings, vectorstore
│   │   ├── services/       # Business logic
│   │   ├── models/         # SQLAlchemy models
│   │   └── utils/          # Parsing, chunking
│   └── tests/
├── harvester/              # Web harvesting service
├── frontend/               # Next.js dashboard
├── docker/                 # Docker configs
└── infrastructure/         # AWS Terraform/CDK
```

## Documentation

- [Implementation Status](./IMPLEMENTATION_STATUS.md) - Detailed progress & next steps
- [Architecture Document](./Hybrid%20RAG%20Architecture.pdf) - Original design spec

## License

Proprietary - Internal Use Only
