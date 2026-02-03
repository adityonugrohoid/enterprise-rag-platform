"""Configuration for Streamlit UI."""
import os
from pathlib import Path

# Project paths
PROJECT_ROOT = Path(__file__).parent.parent
DOCUMENTS_DIR = PROJECT_ROOT / "data" / "documents"

# API Configuration
API_GATEWAY_URL = os.getenv("API_GATEWAY_URL", "http://localhost:8080")
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
API_KEY = os.getenv("API_KEY", "dev-api-key")

# LLM Configuration
LLM_MODEL = os.getenv("LLM_MODEL", "llama3.2:3b")

# UI Configuration
PAGE_TITLE = "Enterprise RAG Platform"
PAGE_ICON = "🤖"
LAYOUT = "wide"

# Supported document extensions
SUPPORTED_EXTENSIONS = [".txt", ".pdf", ".docx"]
