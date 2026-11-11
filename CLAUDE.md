# Healthcare Knowledge Management System (KMS)

## Project Overview
AI-powered document management and retrieval platform for healthcare organizations. Streamlit multi-page app with hybrid RAG search (vector + keyword + structured field matching).

## Architecture
- **Frontend**: Streamlit multi-page app (Python 3.11)
- **Vector Search**: AWS OpenSearch k-NN (HNSW/nmslib, 1024-dim AWS Titan embeddings)
- **Database**: PostgreSQL (RDS) for metadata, chat history, user sessions
- **LLM**: Amazon Nova Lite via LiteLLM gateway for response generation
- **Deployment**: AWS ECS Fargate + ECR + ALB + managed OpenSearch + RDS

## Key Files

### Pages
- `backend/Home.py` — Dashboard + login page
- `backend/pages/1_Upload.py` — Document upload, processing (Excel/PDF/DOCX/Text), OpenSearch indexing, URL validation. Contains 4 processors, OpenSearch schema, sidebar with indexed files
- `backend/pages/2_Chat.py` — Hybrid search (KNN + multi_match + term match) + LLM response generation
- `backend/pages/3_Data_Viewer.py` — Data inspection per file, mismatch detection (document vs web-extracted phone/email)

### Utilities
- `backend/utils/column_mapper.py` — Column detection (fuzzy matching, 0.5 threshold) + `parse_address_components()` for zip/city/state extraction from address strings
- `backend/utils/url_enricher.py` — URL validation (HEAD→GET fallback), metadata extraction (title, description, phone, email from HTML)
- `backend/utils/chunker.py` — Text chunking (sentence-boundary, paragraph-grouping, page-based)
- `backend/utils/contextual_chunker.py` — **[Phase 1]** Contextual retrieval: LLM-generated headers for chunks, `embed_with_context()`, document metadata generation for Excel/PDF/DOCX/Text
- `backend/utils/query_processor.py` — **[Phase 1]** Query decomposition: extract main query, filters (county, city, category), sub-queries; `build_opensearch_filters()` for filter clauses
- `backend/utils/auth.py` — Admin auth via streamlit-authenticator, AWS Secrets Manager in production
- `backend/utils/db.py` — Synchronous PostgreSQL operations (SQLAlchemy)
- `backend/utils/styles.py` — CSS theming, `render_sidebar_header()`, navigation links
- `backend/utils/theme.py` — DARK_COLORS / LIGHT_COLORS dicts, `get_colors()`

### Infrastructure
- `infrastructure/terraform/` — Full AWS IaC (VPC, ECS, RDS, OpenSearch, ALB, ECR)
- `infrastructure/terraform/terraform.tfvars` — App image tag, instance sizes, costs
- `docker/backend/Dockerfile` — Python 3.11-slim, Tesseract OCR, poppler
- `deploy.sh` — Builds linux/amd64 image, pushes ECR, updates ECS task definition

### Documentation
- `temp/IMPLEMENTATION_STATUS.md` — Full implementation history (UI Phases 1-8)
- `docs/CODE_WALKTHROUGH.md` — Technical deep-dive into all components
- `docs/FUNCTIONAL_DOCUMENTATION.md` — Feature specifications and diagrams

## OpenSearch Schema (index: knowledge_base)
Key fields: `embedding` (knn_vector 1024), `text`, `resource_name`, `website_url`, `phone`, `email`, `category_field`, `county`, `zip_code`, `city`, `state`, `url_valid`, `url_title`, `url_description`, `url_extracted_phone`, `url_extracted_email`, `filename`, `document_type`, `indexed_at`

**Phase 1 Additions (Advanced RAG)**:
- `context_header` (text) — LLM-generated contextual header prepended to chunk before embedding (improves retrieval by ~49%)
- `parent_chunk_id` (keyword) — Reserved for Phase 2 hierarchical parent-child chunking
- Enhanced `_source` fields: `services`, `description`, `eligibility`, `hours` — Full structured metadata passed to LLM for better responses

## Advanced RAG Implementation (Phase 1 - Feb 2026)

### Contextual Retrieval
- **Problem**: Basic chunking loses document context → poor retrieval accuracy
- **Solution**: Generate LLM-powered contextual headers for each chunk before embedding
- **Implementation**: ✅ **Complete for all formats (Excel, PDF, DOCX, Text)**
  - Excel: `create_document_metadata_excel()` analyzes sheets → generates sheet descriptions → creates per-row context headers
  - PDF: `create_document_metadata_pdf()` captures page structure → creates per-chunk context with page numbers
  - DOCX: `create_document_metadata_docx()` captures paragraph structure → creates per-chunk context
  - Text: `create_document_metadata_text()` creates simple document context headers
  - Context prepended to chunk text before embedding: `f"{context_header}\n\n{chunk_text}"`
  - Headers stored in `context_header` field for LLM reference
- **Expected Impact**: ~49% reduction in failed retrievals (Anthropic benchmark)

### Query Decomposition
- **Problem**: Complex queries ("mental health resources for seniors in Lafayette accepting Medicaid") poorly handled
- **Solution**: LLM decomposes query into main query + filters + sub-queries
- **Implementation**:
  - `decompose_query()` extracts: main_query, filters (county, city, zip, category), sub_queries
  - Filters converted to OpenSearch filter clauses via `build_opensearch_filters()`
  - Main query + sub-queries executed, results deduplicated
- **Expected Impact**: 15-20% better handling of multi-faceted queries

### Enhanced LLM Context
- **Problem**: Flat context stack, structured metadata not passed to LLM → hallucinations
- **Solution**: Format search results with full structured metadata
- **Implementation**:
  - `generate_response()` builds metadata blocks: 📄 Source, 🏢 Resource, 📞 Phone, 🌐 Website, etc.
  - Includes context_header, services, description, eligibility, hours
  - Separators (─) for clear visual structure
- **Expected Impact**: 30-40% improvement in answer quality, reduced hallucinations

### Cost Analysis
- **One-time**: Louisiana file (394 rows) re-indexing: ~$0.04 (context headers + re-embedding)
- **Per-query**: +$0.000012 (query decomposition via Nova Lite)
- **Total per query**: ~$0.000042 (was $0.00003) — 40% increase, still <$1/1000 queries

## Important Patterns
- **Document `_id`**: Must be set as `f"{document_id}_{idx}"` in all 4 processors — required for URL validation UPDATE operations
- **Contextual embeddings**: Use `embed_with_context()` instead of direct `get_embeddings_sync()` for Phase 1 enhancements
- **Query processing**: Always call `decompose_query()` before search to extract filters and improve complex query handling
- **Column mapper**: "parish" maps to county (Louisiana data). Address parsing fallback extracts city/state/zip when explicit columns don't exist
- **CSS overrides**: `config.toml` is static at server startup — dynamic theming requires `!important` overrides
- **OpenSearch is VPC-internal**: Can't query from local machine; use CloudWatch logs at `/ecs/healthcare-kb` for debugging
- **Deploy**: `./deploy.sh <version-tag>` builds, pushes ECR, updates ECS. Current tag: `v-data-viewer`

## Development
```bash
# Local Docker stack
docker compose -f docker/docker-compose.local.yml up --build -d

# Deploy to AWS
./deploy.sh v-<version-tag>

# View ECS logs
aws logs tail /ecs/healthcare-kb --follow
```

## Current State (Feb 9, 2026)
- UI Phases 1-8 complete, deployed as `v-data-viewer`
- **Advanced RAG Phase 1 COMPLETE** (branch: `feature/advanced-rag-phase-1`):
  - ✅ Contextual retrieval with LLM-generated headers (ALL formats: Excel, PDF, DOCX, Text)
  - ✅ Query decomposition with filter extraction
  - ✅ Enhanced LLM context with structured metadata
  - ✅ Phone wildcard search with location filtering
  - ✅ Regression test suite
  - ⏳ Pending: Deployment to production
- App URL: <ALB_HOSTNAME>
- **Important**: After deploying Phase 1, re-upload ALL documents (Excel/PDF/DOCX/Text) to generate contextual embeddings and benefit from ~49% improved retrieval
