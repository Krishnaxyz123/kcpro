# KMS — end-to-end orientation

Written for an engineer seeing this codebase for the first time, with no access to the
company's AWS accounts. It explains what the system does, how a request flows through it,
and how it is built and deployed. Existing deep-dives live in `docs/`; this file is the map
that ties them together.

> **This is a sanitised copy.** Git history has been removed entirely, and account IDs,
> hostnames, domains and similar identifiers are replaced with `<PLACEHOLDERS>`. See
> *"What was masked"* at the end. Everything else is the real code.

---

## 1. What the system is

A **retrieval system for community health resources**. Care extenders (care navigators)
need to answer "what dental clinics near this member take Medicaid?" — so the platform
ingests resource directories (Excel, PDF, DOCX, text), indexes them for semantic search,
and serves two different audiences:

- **Admins / content owners** use a Streamlit console to upload documents, inspect what got
  indexed, and test searches.
- **The mMR mobile app**, via a separate REST API, gets *structured referral cards* for a
  member — not prose. That API is the production consumer.

A third, newer flow brokers **AI-generated clinical case notes** between the Streamlit
console and an external case-note service (section 5).

## 2. Three runtimes, and why

| Runtime | What it is | Where it runs |
|---|---|---|
| **Streamlit console** | `backend/Home.py` + `backend/pages/*` | ECS Fargate, behind an ALB |
| **Ingestion worker** | `backend/utils/ingestion_worker.py` | *the same container* as Streamlit |
| **Referral/chat API** | `backend/api/` (FastAPI + Mangum) | Lambda, behind API Gateway |

Two things usually surprise people here.

**The worker shares the Streamlit container.** `docker/backend/Dockerfile` ends with
`python utils/ingestion_worker.py & streamlit run Home.py`. Uploading a large spreadsheet
enqueues a job row; the background process picks it up so the UI isn't blocked.

**The Lambda deliberately runs a *subset* of the API.** `backend/api/main.py` imports the
`admin` and `jobs` routers inside `try/except ImportError`, because they need SQLAlchemy and
a Postgres driver that the slim Lambda image doesn't ship. Those endpoints exist only where
the DB layer is present. Adding a DB import to a Lambda-loaded module takes down the whole
referral API — this has happened and was reverted.

## 3. The RAG pipeline

### Ingestion — `backend/utils/ingestion_graph.py` (LangGraph)

```
analyze_document → chunk_content → extract_entities
                 → generate_headers_and_embed → index_chunks → enrich_urls
```

- **chunk_content** — `chunker.py` splits on sentence/paragraph/page boundaries. For Excel,
  one row is one chunk, because a row *is* a resource.
- **generate_headers_and_embed** — the interesting step. Before embedding, an LLM writes a
  short **context header** describing where the chunk sits in its document, and the header is
  prepended to the chunk text (`contextual_chunker.py`). A row reading `"Smith Dental, 555-0100"`
  embeds as *"Dental providers in Lafayette Parish, Louisiana… Smith Dental, 555-0100"*. This
  is Anthropic's contextual-retrieval technique; it exists because bare table rows embed poorly.
- **index_chunks** — writes to OpenSearch: a 1024-dim Titan embedding (`knn_vector`, HNSW)
  plus structured fields (`city`, `county`, `zip_code`, `category_field`, `phone`, …).
- **enrich_urls** — `url_enricher.py` validates each resource URL and pulls title/description/
  phone/e-mail from the page, so stale directory data can be spotted.

### Retrieval — `backend/utils/search_graph.py` (LangGraph)

```
classify_and_prepare → search → evaluate → (reformulate → search)* → generate
```

The loop is the point: the graph **grades its own results** and, if they're weak, rewrites the
query and searches again before answering. Supporting pieces:

- `query_processor.py` — decomposes "mental health resources for seniors in Lafayette accepting
  Medicaid" into a main query, structured **filters** (county/city/category) and sub-queries.
- `search_utils.py` — the hybrid query itself: k-NN vector search **plus** keyword `multi_match`
  **plus** `term` filters. Semantic similarity alone can't honour "in Lafayette".
- `category_hierarchy.py` — the canonical taxonomy the mobile app's categories map onto.
- `query_logger.py` — records queries and outcomes, which is how retrieval gaps get found.

## 4. The mMR API — how the mobile app connects

`backend/api/routers/query.py` is the production surface and the largest single file. It
serves `POST /api/v1/query`, returning **referral cards**, not chat text. Read it for:
dual-section results, "safe loosening" when strict filters return nothing, brand boosting,
composite dedup, and session continuation (pass back a prior `message_id` with "any more?"
to page without spending another LLM call).

Other endpoints: `POST /chat` (full agentic answer), `POST /quick_actions` (context-aware
suggestion buttons), `POST /token` (JWT). `/api/v2` duplicates chat and query behind hardened
auth while v1 is sunset.

## 5. The case-note broker — a worked example of an integration constraint

The Streamlit **Case Note** page (`backend/pages/4_Case_Note.py`) generates a clinical DAP
note from a session transcript. It no longer calls the case-note service directly, and the
reason is worth understanding:

The service is **asynchronous** — it answers `202 + note_id` and delivers the finished note by
**webhook to a single configured URL**, with no polling endpoint. That URL belongs to mmr-api
(the main clinical Rails backend). KMS therefore *cannot* receive its own notes without
stealing mmr-api's deliveries.

So mmr-api brokers both halves: it submits on KMS's behalf, registers the `note_id`, parks the
webhook delivery in Redis, and KMS collects it by `note_id`. Hence the page's two steps —
**Generate Note**, then **Check for result** — instead of one blocking call. A note that nobody
registered is never parked, which is what keeps real members' notes out of that path.

## 6. Data stores

| Store | Holds |
|---|---|
| **OpenSearch** | the vector index — embeddings + structured resource fields |
| **PostgreSQL (RDS)** | document metadata, chat history, ingestion jobs, Excel row hashes (`backend/src/models/`) |
| **Secrets Manager** | DB URL, LLM gateway key, external API credentials |

Models are the quickest way to see the relational side: `document.py`, `chat.py`,
`ingestion_job.py`, `excel_row_hash.py` (row hashes make re-uploads idempotent).

LLM calls go through a **LiteLLM gateway** rather than direct to the provider, so models can be
swapped centrally. Embeddings are AWS Titan via Bedrock.

## 7. How it ships

**Two images, two targets.** `docker/backend/Dockerfile` → ECS Fargate (Streamlit + worker);
`docker/lambda/Dockerfile` → Lambda (FastAPI). Both pushed to ECR, tagged `sha-<commit>`.

**Terraform** (`infrastructure/terraform/`) owns everything: `main.tf` (VPC, subnets, IAM),
`ecs.tf` (cluster, task definition, service, ALB), `lambda.tf` (function, API Gateway),
`secrets.tf` (Secrets Manager wiring + execution-role grants), `alarms.tf`, `waf.tf`, `dns.tf`.
Per-environment values live in `envs/*.tfvars`.

**GitHub Actions:**
- `ci.yml` — on PRs: `terraform fmt -check`, `validate`, and a real `terraform plan` posted as a
  PR comment. A failing plan fails the PR.
- `deploy.yml` — on push to the staging branch: build both images → push to ECR →
  `terraform apply`. Production requires an approval gate.

**Secrets are never in the repo.** Terraform reads only secret *ARNs*; the ECS agent injects the
values at container start. A secret that doesn't exist fails the plan — deliberately.

Note the deploy rhythm: a green pipeline means "new task launched", not "users see it". ECS
runs old and new tasks together until the new one passes ALB health checks, and the target
group uses **stickiness** (Streamlit needs it for its websocket), so your own browser is the
last thing to move across.

## 8. Local development

```bash
docker compose -f docker/docker-compose.local.yml up --build -d
```

Brings up Streamlit, Postgres and OpenSearch locally. Copy `.env.example` to `.env` and fill in
AWS credentials for Bedrock embeddings and a LiteLLM key. Login is admin / `ADMIN_PASSWORD`.

## 9. Suggested reading order

1. `README.md`, then this file
2. `backend/Home.py` and `backend/pages/` — the console, smallest surface
3. `backend/utils/ingestion_graph.py` → `contextual_chunker.py` — how data gets in
4. `backend/utils/search_graph.py` → `search_utils.py` → `query_processor.py` — how it comes out
5. `backend/api/routers/query.py` — the production API (dense; read last)
6. `infrastructure/terraform/ecs.tf` and `.github/workflows/deploy.yml` — how it ships
7. `docs/CODE_WALKTHROUGH.md`, `docs/FUNCTIONAL_DOCUMENTATION.md`, `docs/search-flow.md`

## 10. What was masked, and what isn't real

Replaced with placeholders: AWS account IDs (`<SANDBOX_ACCOUNT_ID>`, `<PROD_ACCOUNT_ID>`,
`<AUDIT_ACCOUNT_ID>`), load-balancer and API Gateway hostnames (`<ALB_HOSTNAME>`,
`<CASE_NOTE_API_URL>`), company domains and e-mail addresses (`<APP_DOMAIN>`, `<MMR_API_HOST>`,
`@example.com`), the Route53 hosted zone, the audit log bucket, VPC/subnet/security-group ids,
and the GitHub org/repo in the OIDC trust policy (`<GITHUB_ORG>/<REPO>`).

Kept on purpose, because they teach the design and are useless without account access: private
CIDRs, IAM policy shapes, resource naming conventions, and Secrets Manager key names.

Removed: all git history, and a report of real production queries.

**`harvester/` is a stub** — package skeleton only, about seven lines of Python. It's a planned
web-harvesting service, not working code. Don't go looking for logic there.
