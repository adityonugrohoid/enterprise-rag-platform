#!/bin/bash
# Debug script to check service status and diagnose issues

echo "========================================="
echo "Service Diagnostics"
echo "========================================="
echo ""

# Check Docker services
echo "1. Docker Services:"
docker compose ps 2>/dev/null || echo "  ⚠ Docker not accessible"
echo ""

# Check backend services
echo "2. Backend Services:"
for port in 8001 8002 8003 8080; do
    service_name=""
    case $port in
        8001) service_name="Ingestion" ;;
        8002) service_name="Retrieval" ;;
        8003) service_name="Query" ;;
        8080) service_name="API Gateway" ;;
    esac
    
    if curl -s -f "http://localhost:${port}/health" > /dev/null 2>&1; then
        echo "  ✅ ${service_name} (port ${port}) - Running"
        response=$(curl -s "http://localhost:${port}/health")
        echo "     Response: $response"
    else
        echo "  ❌ ${service_name} (port ${port}) - Not responding"
    fi
done
echo ""

# Check ChromaDB
echo "3. ChromaDB:"
if curl -s -f "http://localhost:8000/api/v2/heartbeat" > /dev/null 2>&1; then
    echo "  ✅ ChromaDB is running (v2 API)"
    # Try to get heartbeat response
    heartbeat=$(curl -s "http://localhost:8000/api/v2/heartbeat" 2>/dev/null || echo "unknown")
    echo "     Heartbeat: $heartbeat"
else
    echo "  ❌ ChromaDB is not responding"
    echo "     Trying v1 API (deprecated)..."
    if curl -s -f "http://localhost:8000/api/v1/heartbeat" > /dev/null 2>&1; then
        echo "  ⚠ ChromaDB responding on v1 API (deprecated)"
    fi
fi
echo ""

# Check Ollama
echo "4. Ollama:"
if curl -s -f "http://localhost:11434/api/tags" > /dev/null 2>&1; then
    echo "  ✅ Ollama is running"
    models=$(curl -s "http://localhost:11434/api/tags" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join([m['name'] for m in data.get('models', [])]))" 2>/dev/null || echo "unknown")
    echo "     Available models: $models"
else
    echo "  ❌ Ollama is not responding"
fi
echo ""

# Test retrieval service directly
echo "5. Testing Retrieval Service:"
if curl -s -f "http://localhost:8002/health" > /dev/null 2>&1; then
    test_response=$(curl -s -X POST http://localhost:8002/retrieve \
        -H "Content-Type: application/json" \
        -d '{"query": "test", "top_k": 1}' 2>&1)
    if echo "$test_response" | grep -q "chunks"; then
        echo "  ✅ Retrieval service is working"
    else
        echo "  ⚠ Retrieval service responded but may have issues:"
        echo "     $test_response"
    fi
else
    echo "  ❌ Retrieval service is not running"
fi
echo ""

# Test query service directly
echo "6. Testing Query Service:"
if curl -s -f "http://localhost:8003/health" > /dev/null 2>&1; then
    test_response=$(curl -s -X POST http://localhost:8003/query \
        -H "Content-Type: application/json" \
        -d '{"query": "test"}' 2>&1)
    if echo "$test_response" | grep -q "answer\|success"; then
        echo "  ✅ Query service is working"
    else
        echo "  ⚠ Query service responded but may have issues:"
        echo "     $test_response"
    fi
else
    echo "  ❌ Query service is not running"
fi
echo ""

echo "========================================="
echo "Diagnostics Complete"
echo "========================================="
