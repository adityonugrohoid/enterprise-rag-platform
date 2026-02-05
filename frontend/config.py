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

# Use case categories - maps to document subdirectories
USE_CASES = {
    "telecom": {
        "label": "Telecom",
        "icon": "📡",
        "description": "Network performance, RAN optimization, OSS/BSS integration"
    },
    "enterprise": {
        "label": "Enterprise",
        "icon": "🏢",
        "description": "HR policies, employee handbook, IT security"
    },
    "support": {
        "label": "Support",
        "icon": "🎧",
        "description": "Customer support, troubleshooting, product FAQ"
    },
    "legal": {
        "label": "Legal",
        "icon": "⚖️",
        "description": "Privacy policy, data retention, compliance"
    },
    "education": {
        "label": "Education",
        "icon": "🎓",
        "description": "Training materials, onboarding, tutorials"
    },
    "technical": {
        "label": "Technical",
        "icon": "🔧",
        "description": "API reference, SDK documentation, technical guides"
    }
}

# Pre-defined questions organized by document topic
# These questions are designed to test the RAG system with relevant queries
PREDEFINED_QUESTIONS = {
    # === ENTERPRISE KNOWLEDGE BASE ===
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

    # === HR & EMPLOYEE POLICIES ===
    "Employee Handbook": [
        "What is the PTO policy for employees with 5 years of tenure?",
        "How many sick days do employees get per year?",
        "What is the parental leave policy for birth parents?",
        "What are the standard work hours and core hours?",
        "What is the remote work policy and requirements?",
        "What is the 401(k) company match percentage?",
        "What health insurance plans are offered?",
        "What is the dress code policy?",
        "How do I report harassment or ethics violations?",
        "What is the resignation notice period requirement?",
    ],
    "IT Security Procedures": [
        "What are the password requirements for TechCorp systems?",
        "How do I set up multi-factor authentication (MFA)?",
        "What is the process for requesting system access?",
        "What should I do if my device is lost or stolen?",
        "What are the VPN requirements for remote work?",
        "How do I report a phishing email?",
        "What is the data classification policy?",
        "What are the approved storage locations for confidential data?",
        "What is the incident response process?",
        "How often are access reviews conducted?",
    ],

    # === CUSTOMER SUPPORT ===
    "Product Troubleshooting": [
        "How do I fix sync failures in CloudSync?",
        "What does error code CS-401 mean?",
        "Why are my photos not backing up on iOS?",
        "How do I fix high CPU usage during sync?",
        "What are the steps to reset my password?",
        "How do I fix the 'Missing Visual C++ Runtime' error?",
        "Why is the Mac installation being blocked?",
        "How do I enable background sync on Android?",
        "What should I do if sync is very slow?",
        "How do I contact customer support?",
    ],
    "Product Features": [
        "What is Smart Sync and how does it work?",
        "How do I enable Selective Sync?",
        "What is the file versioning retention period?",
        "How do I share files with external users?",
        "What encryption does CloudSync use?",
        "How do I set up two-factor authentication?",
        "What is the Remote Wipe feature?",
        "How do I integrate with Microsoft 365?",
        "What are the API rate limits?",
        "How do I set storage quotas for team members?",
    ],

    # === LEGAL & COMPLIANCE ===
    "Privacy Policy": [
        "What personal data does TechCorp collect?",
        "How is my data used for marketing purposes?",
        "What are my data protection rights?",
        "How do I request deletion of my data?",
        "What cookies does the website use?",
        "How is data transferred internationally?",
        "Who are the third-party service providers?",
        "How long is personal data retained?",
        "How do I withdraw consent for data processing?",
        "Who is the Data Protection Officer?",
    ],
    "Data Retention Policy": [
        "How long are customer transaction records retained?",
        "What is the retention period for employee records?",
        "How are documents securely disposed?",
        "What is a legal hold and when is it applied?",
        "What is the retention period for system logs?",
        "How often are retention audits conducted?",
        "What are the hardware disposal procedures?",
        "Who approves exceptions to the retention policy?",
        "What is the backup data retention period?",
        "How is paper document disposal handled?",
    ],

    # === EDUCATION & TRAINING ===
    "Machine Learning Fundamentals": [
        "What is the difference between supervised and unsupervised learning?",
        "What is the difference between precision and recall?",
        "How do I handle missing data in a dataset?",
        "What is feature scaling and when should I use it?",
        "What is cross-validation and why is it important?",
        "What is overfitting and how can I prevent it?",
        "What is the bias-variance tradeoff?",
        "What is L1 vs L2 regularization?",
        "How do I encode categorical variables?",
        "What is the F1 score and when should I use it?",
    ],
    "Python Programming": [
        "How do I create and modify a list in Python?",
        "What is the difference between a list and a tuple?",
        "How do I use dictionary comprehension?",
        "What are f-strings and how do I use them?",
        "How do I read and write files in Python?",
        "What is a lambda function?",
        "How do I use *args and **kwargs?",
        "What is the difference between == and is?",
        "How do I handle exceptions in Python?",
        "What is list slicing and how does it work?",
    ],

    # === TECHNICAL API REFERENCE (RAG Differentiator) ===
    "Internal API Reference": [
        "What is the API key format for TechCorp API?",
        "What are the API rate limits for enterprise tier?",
        "What does error code TC-409-USR-010 mean?",
        "How do I authenticate with the TechCorp API?",
        "What is the hourly cost for GPU compute instances?",
        "How do I install and initialize the TechCorp Python SDK?",
        "What fields are required to create a new user via API?",
        "How do I verify webhook signatures?",
        "What is the base URL for the production API?",
        "What is the project allocation percentage limit?",
        "What SKU codes are available for cloud compute?",
        "What are the sandbox test credentials?",
    ],
}

# Map question categories to use cases
CATEGORY_TO_USE_CASE = {
    # Telecom
    "Network Performance Standards": "telecom",
    "RAN Optimization Procedures": "telecom",
    "OSS/BSS Integration": "telecom",
    # Enterprise
    "Employee Handbook": "enterprise",
    "IT Security Procedures": "enterprise",
    # Support
    "Product Troubleshooting": "support",
    "Product Features": "support",
    # Legal
    "Privacy Policy": "legal",
    "Data Retention Policy": "legal",
    # Education
    "Machine Learning Fundamentals": "education",
    "Python Programming": "education",
    # Technical
    "Internal API Reference": "technical",
}


def get_questions_by_use_case(use_case: str = "all") -> dict:
    """Return questions filtered by use case."""
    if use_case == "all":
        return PREDEFINED_QUESTIONS

    filtered = {}
    for category, questions in PREDEFINED_QUESTIONS.items():
        if CATEGORY_TO_USE_CASE.get(category) == use_case:
            filtered[category] = questions
    return filtered


# Flatten questions for dropdown with category prefix
def get_all_questions_with_categories():
    """Return list of (display_text, question) tuples for dropdown."""
    questions = [("-- Select a question or type your own --", "")]
    for category, q_list in PREDEFINED_QUESTIONS.items():
        for q in q_list:
            display = f"[{category[:15]}...] {q[:60]}..." if len(q) > 60 else f"[{category[:15]}...] {q}"
            questions.append((display, q))
    return questions
