#!/bin/bash
# Start all backend services for Enterprise RAG Platform

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${GREEN}Starting Enterprise RAG Platform Services${NC}"
echo ""

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo -e "${YELLOW}Creating virtual environment...${NC}"
    python3 -m venv .venv
fi

# Activate virtual environment
source .venv/bin/activate

# Check if dependencies are installed
if ! python3 -c "import fastapi" 2>/dev/null; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    pip install -q -r requirements.txt
fi

# Function to check if port is in use
is_port_in_use() {
    local port=$1
    lsof -i :${port} > /dev/null 2>&1
}

# Function to kill process on port
kill_port() {
    local port=$1
    local pid=$(lsof -t -i:${port} 2>/dev/null)
    if [ -n "$pid" ]; then
        echo -e "${YELLOW}Killing existing process on port ${port} (PID: ${pid})...${NC}"
        kill $pid 2>/dev/null || true
        sleep 1
    fi
}

# Function to start a service in background
start_service() {
    local service_name=$1
    local service_file=$2
    local port=$3
    
    # Check if port is already in use
    if is_port_in_use $port; then
        echo -e "${YELLOW}Port ${port} is already in use. Checking if it's our service...${NC}"
        # Check if it's our service by checking the PID file
        if [ -f "logs/${service_name}.pid" ]; then
            local existing_pid=$(cat "logs/${service_name}.pid" 2>/dev/null)
            local port_pid=$(lsof -t -i:${port} 2>/dev/null)
            if [ "$existing_pid" = "$port_pid" ] && ps -p $existing_pid > /dev/null 2>&1; then
                echo -e "${GREEN}✓ ${service_name} is already running (PID: ${existing_pid})${NC}"
                return 0
            fi
        fi
        # Kill existing process on port
        kill_port $port
    fi
    
    echo -e "${GREEN}Starting ${service_name} on port ${port}...${NC}"
    python3 "$service_file" > "logs/${service_name}.log" 2>&1 &
    local pid=$!
    echo $pid > "logs/${service_name}.pid"
    sleep 3
    
    # Check if service started successfully
    if curl -s -f "http://localhost:${port}/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ ${service_name} is running (PID: ${pid})${NC}"
    else
        echo -e "${YELLOW}⚠ ${service_name} may still be starting...${NC}"
        echo -e "${YELLOW}   Check logs: tail -f logs/${service_name}.log${NC}"
    fi
}

# Create logs directory
mkdir -p logs

# Start services
start_service "ingestion" "services/ingestion/main.py" "8001"
start_service "retrieval" "services/retrieval/main.py" "8002"
start_service "query" "services/query/main.py" "8003"
start_service "api_gateway" "services/api_gateway/main.py" "8080"

echo ""
echo -e "${GREEN}All services started!${NC}"
echo ""
echo "Service URLs:"
echo "  - API Gateway: http://localhost:8080"
echo "  - Ingestion: http://localhost:8001"
echo "  - Retrieval: http://localhost:8002"
echo "  - Query: http://localhost:8003"
echo ""
echo "Logs are in: logs/"
echo "PIDs are in: logs/*.pid"
echo ""
echo "To stop services, run: bash scripts/stop_services.sh"
