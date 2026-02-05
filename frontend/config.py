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

# Pre-defined questions organized by document topic
# These questions are designed to test the RAG system with relevant queries
PREDEFINED_QUESTIONS = {
    "Network Performance Standards": [
        "What are the 5G RAN performance targets for accessibility KPIs?",
        "What is the target E2E Call Drop Rate and how is it measured?",
        "What are the handover success rate targets for 5G and LTE?",
        "What throughput and latency targets should 5G networks achieve?",
        "What are the SLA targets for Premium vs Standard customers?",
        "How is incident priority classified (P1, P2, P3)?",
        "What are the troubleshooting steps for high call drop rate?",
        "What causes low throughput and how to fix it?",
        "What is required before making network optimization changes?",
        "What are the emergency procedures for major outages?",
    ],
    "RAN Optimization Procedures": [
        "What are the phases of the RAN optimization workflow?",
        "How should baseline data be collected before optimization?",
        "What parameters should be adjusted for coverage optimization?",
        "How to optimize handover parameters based on cell size?",
        "What is the load balancing configuration process?",
        "How to troubleshoot low RACH success rate?",
        "What causes call drop rate spikes and how to resolve them?",
        "How to handle weekend peak hour congestion?",
        "What are the solutions for cell border ping-pong handovers?",
        "What is the escalation criteria for network issues?",
    ],
    "OSS/BSS Integration": [
        "What is the OSS/BSS integration architecture?",
        "How does data flow from network elements to customer portal?",
        "What KPIs are collected for accessibility and retainability?",
        "How is SLA credit calculated when network availability is breached?",
        "What is the formula for call drop rate credit calculation?",
        "How does the throughput credit calculation work?",
        "What features are available in the customer SLA dashboard?",
        "What is the customer dispute resolution process?",
        "How often is OSS data collected and aggregated?",
        "What are the data quality validation rules?",
    ],
}

# Flatten questions for dropdown with category prefix
def get_all_questions_with_categories():
    """Return list of (display_text, question) tuples for dropdown."""
    questions = [("-- Select a question or type your own --", "")]
    for category, q_list in PREDEFINED_QUESTIONS.items():
        for q in q_list:
            display = f"[{category[:15]}...] {q[:60]}..." if len(q) > 60 else f"[{category[:15]}...] {q}"
            questions.append((display, q))
    return questions
