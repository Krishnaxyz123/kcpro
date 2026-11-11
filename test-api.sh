#!/bin/bash
# Test FastAPI Agentic Chat API

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Testing FastAPI Agentic Chat API ===${NC}\n"

# 1. Health check
echo -e "${BLUE}1. Health Check${NC}"
curl -s http://localhost:8000/api/health | python3 -m json.tool
echo -e "\n"

# 2. Get JWT token
echo -e "${BLUE}2. Authenticating (username: demo, password: demo)${NC}"
TOKEN_RESPONSE=$(curl -s -X POST http://localhost:8000/api/v1/token \
  -H "Content-Type: application/json" \
  -d '{"username": "demo", "password": "demo"}')

TOKEN=$(echo $TOKEN_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
echo -e "${GREEN}Token received:${NC} ${TOKEN:0:50}..."
echo -e "\n"

# 3. Test chat endpoint
echo -e "${BLUE}3. Testing Chat Endpoint${NC}"
echo -e "Query: ${GREEN}How do I get help with behavioral health in Florida?${NC}\n"

curl -s -X POST http://localhost:8000/api/v1/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "query": "How do I get help with behavioral health in Florida?",
    "top_k": 3
  }' | python3 -m json.tool

echo -e "\n${GREEN}=== Tests Complete ===${NC}"
