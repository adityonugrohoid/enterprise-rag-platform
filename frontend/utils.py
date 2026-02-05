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


def scan_documents() -> Dict[str, List[str]]:
    """
    Scan the documents directory for supported files, organized by category.

    Returns:
        Dictionary mapping category names to lists of document filenames
    """
    if not DOCUMENTS_DIR.exists():
        return {}

    documents_by_category = {}

    # Scan subdirectories (categories)
    for category_dir in sorted(DOCUMENTS_DIR.iterdir()):
        if category_dir.is_dir() and not category_dir.name.startswith('.'):
            category_name = category_dir.name
            category_docs = []

            for ext in SUPPORTED_EXTENSIONS:
                category_docs.extend([f.name for f in category_dir.glob(f"*{ext}")])

            # Filter out system files
            category_docs = [d for d in category_docs if not d.startswith('.')]

            if category_docs:
                documents_by_category[category_name] = sorted(category_docs)

    return documents_by_category


def scan_documents_flat() -> List[str]:
    """
    Scan the documents directory for supported files (flat list with paths).

    Returns:
        List of relative document paths (category/filename)
    """
    if not DOCUMENTS_DIR.exists():
        return []

    documents = []

    # Scan subdirectories (categories)
    for category_dir in sorted(DOCUMENTS_DIR.iterdir()):
        if category_dir.is_dir() and not category_dir.name.startswith('.'):
            for ext in SUPPORTED_EXTENSIONS:
                for f in category_dir.glob(f"*{ext}"):
                    if not f.name.startswith('.'):
                        documents.append(f"{category_dir.name}/{f.name}")

    return sorted(documents)


def upload_document(doc_path: str) -> Tuple[bool, str, Dict]:
    """
    Upload a document to the ingestion service.

    Args:
        doc_path: Path to the document file (category/filename or just filename)

    Returns:
        Tuple of (success, message, data)
    """
    file_path = DOCUMENTS_DIR / doc_path
    filename = Path(doc_path).name
    
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


def get_indexed_document_count() -> Tuple[int, List[str]]:
    """
    Get count and list of documents indexed in the vector database.

    Returns:
        Tuple of (document_count, list_of_document_names)
    """
    try:
        headers = {"X-API-Key": API_KEY}

        with httpx.Client(timeout=10.0) as client:
            # Try to get document list from API if endpoint exists
            response = client.get(
                f"{API_GATEWAY_URL}/documents",
                headers=headers
            )
            if response.status_code == 200:
                data = response.json()
                docs = data.get("documents", [])
                return len(docs), docs
    except:
        pass

    # Fallback: Query ChromaDB directly if available
    try:
        import chromadb
        from chromadb.config import Settings
        client = chromadb.HttpClient(
            host="localhost",
            port=8000,
            settings=Settings(anonymized_telemetry=False)
        )
        collection = client.get_or_create_collection("documents")

        # Get unique document filenames
        results = collection.get(include=["metadatas"])
        if results and results.get("metadatas"):
            filenames = set()
            for meta in results["metadatas"]:
                if meta and "filename" in meta:
                    filenames.add(meta["filename"])
            return len(filenames), sorted(list(filenames))

        # If no metadata, return chunk count estimate
        count = collection.count()
        return count, []
    except:
        pass

    return 0, []


def clear_indexed_documents() -> Tuple[bool, str, int]:
    """
    Clear all documents from the vector database.

    Returns:
        Tuple of (success, message, deleted_count)
    """
    try:
        headers = {"X-API-Key": API_KEY}

        with httpx.Client(timeout=30.0) as client:
            response = client.delete(
                f"{API_GATEWAY_URL}/documents",
                headers=headers
            )
            response.raise_for_status()

            data = response.json()
            deleted_count = data.get("deleted_count", 0)
            return True, f"Cleared {deleted_count} chunks from database", deleted_count

    except httpx.HTTPError as e:
        error_msg = f"HTTP error: {str(e)}"
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_detail = e.response.json().get('detail', str(e))
                error_msg = f"Clear failed: {error_detail}"
            except:
                pass
        return False, error_msg, 0
    except Exception as e:
        return False, f"Error: {str(e)}", 0
