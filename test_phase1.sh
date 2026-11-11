#!/bin/bash

# Phase 1 Advanced RAG Testing Script
# Tests contextual retrieval, query decomposition, and enhanced metadata

set -e

OPENSEARCH_URL="http://localhost:9200"
INDEX_NAME="knowledge_base_vectors"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║       Phase 1 Advanced RAG Testing Script                  ║"
echo "║   Testing: Contextual Retrieval + Query Decomposition      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Check OpenSearch connection
echo "📋 Test 1: OpenSearch Connection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
HEALTH=$(curl -s "${OPENSEARCH_URL}/_cluster/health")
STATUS=$(echo $HEALTH | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
if [ "$STATUS" = "green" ] || [ "$STATUS" = "yellow" ]; then
    echo "✅ OpenSearch is healthy (status: $STATUS)"
else
    echo "❌ OpenSearch is unhealthy (status: $STATUS)"
    exit 1
fi
echo ""

# Test 2: Check index exists
echo "📋 Test 2: Index Existence"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if curl -s "${OPENSEARCH_URL}/${INDEX_NAME}" > /dev/null 2>&1; then
    echo "✅ Index '${INDEX_NAME}' exists"

    # Get document count
    DOC_COUNT=$(curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
    echo "   📊 Documents indexed: $DOC_COUNT"
else
    echo "⚠️  Index '${INDEX_NAME}' does not exist yet"
    echo "   ℹ️  Upload a document via the Streamlit UI to create the index"
fi
echo ""

# Test 3: Check for Phase 1 schema fields
echo "📋 Test 3: Phase 1 Schema Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if curl -s "${OPENSEARCH_URL}/${INDEX_NAME}" > /dev/null 2>&1; then
    MAPPING=$(curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_mapping")

    # Check for context_header field
    if echo "$MAPPING" | grep -q '"context_header"'; then
        echo "✅ 'context_header' field found in schema"
    else
        echo "❌ 'context_header' field NOT found"
        echo "   ℹ️  This is a Phase 1 field - may need to recreate index"
    fi

    # Check for parent_chunk_id field
    if echo "$MAPPING" | grep -q '"parent_chunk_id"'; then
        echo "✅ 'parent_chunk_id' field found in schema (Phase 2 ready)"
    else
        echo "⚠️  'parent_chunk_id' field NOT found"
    fi

    # Check for enhanced metadata fields
    ENHANCED_FIELDS=("services" "description" "eligibility" "hours")
    for field in "${ENHANCED_FIELDS[@]}"; do
        if echo "$MAPPING" | grep -q "\"$field\""; then
            echo "✅ '$field' field found (enhanced metadata)"
        fi
    done
else
    echo "⏭️  Skipping (index doesn't exist yet)"
fi
echo ""

# Test 4: Check for documents with context headers
echo "📋 Test 4: Context Header Population"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if curl -s "${OPENSEARCH_URL}/${INDEX_NAME}" > /dev/null 2>&1; then
    DOCS_WITH_CONTEXT=$(curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query": {"exists": {"field": "context_header"}}}' \
        | grep -o '"count":[0-9]*' | grep -o '[0-9]*')

    if [ ! -z "$DOCS_WITH_CONTEXT" ] && [ "$DOCS_WITH_CONTEXT" -gt 0 ]; then
        echo "✅ $DOCS_WITH_CONTEXT documents have context headers"
        echo ""
        echo "Sample context header:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        curl -s "${OPENSEARCH_URL}/${INDEX_NAME}/_search" \
            -H 'Content-Type: application/json' \
            -d '{
                "size": 1,
                "_source": ["context_header", "sheet_name", "resource_name", "filename"],
                "query": {"exists": {"field": "context_header"}}
            }' | jq -r '.hits.hits[0]._source | "File: " + .filename + "\nSheet: " + (.sheet_name // "N/A") + "\nResource: " + (.resource_name // "N/A") + "\nContext: " + (.context_header // "N/A")' 2>/dev/null || echo "   (jq not available for pretty printing)"
    else
        echo "⚠️  No documents with context headers found"
        echo "   ℹ️  Action needed: Upload documents via Streamlit UI to generate context headers"
        echo "   📍 Go to: http://localhost:8501 → Upload Documents"
    fi
else
    echo "⏭️  Skipping (index doesn't exist yet)"
fi
echo ""

# Test 5: Streamlit app health
echo "📋 Test 5: Streamlit Application Health"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if curl -s "http://localhost:8501/_stcore/health" > /dev/null 2>&1; then
    echo "✅ Streamlit app is responding"
    echo "   🌐 Access UI at: http://localhost:8501"
else
    echo "❌ Streamlit app is not responding"
    echo "   ℹ️  Check logs: docker compose -f docker/docker-compose.local.yml logs streamlit"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Testing Summary                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Next Steps:"
echo "1. Open Streamlit UI: http://localhost:8501"
echo "2. Upload Louisiana_All_Resources_9-21.xlsx"
echo "3. Watch for 'Analyzing document structure' and 'Generating contextual embeddings'"
echo "4. Test Chat with complex queries like:"
echo "   • 'Find food banks in Lafayette'"
echo "   • 'Mental health resources for seniors in Orleans parish'"
echo "5. Verify structured metadata appears in LLM responses (📞, 🌐, 📍)"
echo ""
echo "Monitor logs:"
echo "  docker compose -f docker/docker-compose.local.yml logs -f streamlit"
echo ""
echo "Re-run this test:"
echo "  bash test_phase1.sh"
echo ""
