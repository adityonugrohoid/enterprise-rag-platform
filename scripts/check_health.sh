#!/bin/bash

echo "=== Health Check ==="
echo ""

echo "1. API Gateway (8080):"
curl -s http://localhost:8080/health | jq . || echo "❌ Not responding"

echo -e "\n2. Ingestion Service (8001):"
curl -s http://localhost:8001/health | jq . || echo "❌ Not responding"

echo -e "\n3. Retrieval Service (8002):"
curl -s http://localhost:8002/health | jq . || echo "❌ Not responding"

echo -e "\n4. Query Service (8003):"
curl -s http://localhost:8003/health | jq . || echo "❌ Not responding"

echo -e "\n5. ChromaDB (8000):"
curl -s http://localhost:8000/api/v1/heartbeat || echo "❌ Not responding"

echo -e "\n6. Ollama (11434):"
curl -s http://localhost:11434/api/tags | jq . || echo "❌ Not responding"

echo -e "\n=== Health Check Complete ==="
