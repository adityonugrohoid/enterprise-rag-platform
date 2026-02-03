"""Utility functions for Streamlit UI."""
import httpx
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import json
import time

from config import (
    DOCUMENTS_DIR,
    API_GATEWAY_URL,
    OLLAMA_HOST,
    API_KEY,
    LLM_MODEL,
    SUPPORTED_EXTENSIONS
)


def scan_documents() -> List[str]:
    """
    Scan the documents directory for supported files.
    
    Returns:
        List of document filenames
    """
    if not DOCUMENTS_DIR.exists():
        return []
    
    documents = []
    for ext in SUPPORTED_EXTENSIONS:
        documents.extend([f.name for f in DOCUMENTS_DIR.glob(f"*{ext}")])
    
    # Filter out .gitkeep and other system files
    documents = [d for d in documents if not d.startswith('.')]
    return sorted(documents)


def upload_document(filename: str) -> Tuple[bool, str, Dict]:
    """
    Upload a document to the ingestion service.
    
    Args:
        filename: Name of the document file
        
    Returns:
        Tuple of (success, message, data)
    """
    file_path = DOCUMENTS_DIR / filename
    
    if not file_path.exists():
        return False, f"File not found: {filename}", {}
    
    try:
        with open(file_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            headers = {"X-API-Key": API_KEY}
            
            with httpx.Client(timeout=60.0) as client:
                response = client.post(
                    f"{API_GATEWAY_URL}/documents/upload",
                    files=files,
                    headers=headers
                )
                response.raise_for_status()
                data = response.json()
                
                return True, f"Successfully ingested {filename}", data
                
    except httpx.HTTPError as e:
        error_msg = f"HTTP error: {str(e)}"
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_detail = e.response.json().get('detail', str(e))
                error_msg = f"Upload failed: {error_detail}"
            except:
                pass
        return False, error_msg, {}
    except Exception as e:
        return False, f"Error uploading {filename}: {str(e)}", {}


def query_with_rag(query: str) -> Tuple[bool, str, Dict]:
    """
    Query the RAG system through API Gateway.
    
    Args:
        query: User's query text
        
    Returns:
        Tuple of (success, response_text, metadata)
    """
    try:
        headers = {
            "X-API-Key": API_KEY,
            "Content-Type": "application/json"
        }
        
        payload = {"query": query}
        
        start_time = time.time()
        with httpx.Client(timeout=60.0) as client:
            response = client.post(
                f"{API_GATEWAY_URL}/query",
                json=payload,
                headers=headers
            )
            response.raise_for_status()
            elapsed_time = time.time() - start_time
            
            data = response.json()
            answer = data.get("answer", "")
            sources = data.get("sources", [])
            chunks_used = data.get("chunks_used", 0)
            
            metadata = {
                "sources": sources,
                "chunks_used": chunks_used,
                "elapsed_time": elapsed_time
            }
            
            return True, answer, metadata
            
    except httpx.HTTPError as e:
        error_msg = f"HTTP error: {str(e)}"
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_detail = e.response.json().get('detail', str(e))
                error_msg = f"Query failed: {error_detail}"
            except:
                pass
        return False, error_msg, {}
    except Exception as e:
        return False, f"Error: {str(e)}", {}


def query_direct_llm(query: str) -> Tuple[bool, str, Dict]:
    """
    Query Ollama directly without RAG.
    
    Args:
        query: User's query text
        
    Returns:
        Tuple of (success, response_text, metadata)
    """
    try:
        payload = {
            "model": LLM_MODEL,
            "messages": [
                {
                    "role": "user",
                    "content": query
                }
            ],
            "stream": False
        }
        
        start_time = time.time()
        with httpx.Client(timeout=60.0) as client:
            response = client.post(
                f"{OLLAMA_HOST}/api/chat",
                json=payload
            )
            response.raise_for_status()
            elapsed_time = time.time() - start_time
            
            data = response.json()
            answer = data.get("message", {}).get("content", "")
            
            metadata = {
                "model": LLM_MODEL,
                "elapsed_time": elapsed_time
            }
            
            return True, answer, metadata
            
    except httpx.HTTPError as e:
        error_msg = f"Ollama HTTP error: {str(e)}"
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_detail = e.response.text
                error_msg = f"Ollama query failed: {error_detail[:200]}"
            except:
                pass
        return False, error_msg, {}
    except Exception as e:
        return False, f"Error calling Ollama: {str(e)}", {}


def check_services_health() -> Dict[str, bool]:
    """
    Check health of backend services.
    
    Returns:
        Dictionary with service names and their health status
    """
    health_status = {
        "api_gateway": False,
        "ollama": False
    }
    
    # Check API Gateway
    try:
        with httpx.Client(timeout=5.0) as client:
            response = client.get(f"{API_GATEWAY_URL}/health")
            health_status["api_gateway"] = response.status_code == 200
    except:
        pass
    
    # Check Ollama
    try:
        with httpx.Client(timeout=5.0) as client:
            response = client.get(f"{OLLAMA_HOST}/api/tags")
            health_status["ollama"] = response.status_code == 200
    except:
        pass
    
    return health_status
