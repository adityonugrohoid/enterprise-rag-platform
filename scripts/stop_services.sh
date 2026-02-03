#!/bin/bash
# Stop all backend services for Enterprise RAG Platform

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Stopping Enterprise RAG Platform Services..."
echo ""

# Stop services by PID
for pidfile in logs/*.pid; do
    if [ -f "$pidfile" ]; then
        service_name=$(basename "$pidfile" .pid)
        pid=$(cat "$pidfile")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Stopping $service_name (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            rm "$pidfile"
        fi
    fi
done

# Also kill any remaining Python processes running the services
pkill -f "services/ingestion/main.py" 2>/dev/null || true
pkill -f "services/retrieval/main.py" 2>/dev/null || true
pkill -f "services/query/main.py" 2>/dev/null || true
pkill -f "services/api_gateway/main.py" 2>/dev/null || true

echo "All services stopped."
