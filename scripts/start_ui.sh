#!/bin/bash
# Start Streamlit UI for Enterprise RAG Platform

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${GREEN}Starting Streamlit UI for Enterprise RAG Platform${NC}"
echo ""

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo -e "${YELLOW}Virtual environment not found. Creating...${NC}"
    python3 -m venv .venv
fi

# Activate virtual environment
source .venv/bin/activate

# Check if streamlit is installed
if ! python3 -c "import streamlit" 2>/dev/null; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    pip install -q -r requirements.txt
fi

# Check if backend services are running
echo "Checking backend services..."
if ! curl -s -f "http://localhost:8080/health" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Backend services don't appear to be running.${NC}"
    echo -e "${YELLOW}   Please start them first with: bash scripts/start_services.sh${NC}"
    echo ""
fi

# Start Streamlit
echo -e "${GREEN}Launching Streamlit UI...${NC}"
echo ""
echo "Access the UI at: http://localhost:8501"
echo ""
echo "Press Ctrl+C to stop the UI"
echo ""

# Run Streamlit
cd frontend
streamlit run app.py --server.port 8501 --server.address localhost
