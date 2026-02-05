"""API Gateway for the RAG platform."""
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from fastapi import FastAPI, UploadFile, File, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import httpx
import os
import logging

from shared.utils.logging import setup_logging
from shared.utils.config import Config
from shared.models.schemas import DocumentResponse, QueryRequest, QueryResponse, APIResponse

logger = setup_logging("api_gateway")
app = FastAPI(title="Enterprise RAG Platform API Gateway")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify actual origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize config
config = Config.from_env()

# Service URLs
INGESTION_URL = os.getenv("INGESTION_URL", "http://localhost:8001")
RETRIEVAL_URL = os.getenv("RETRIEVAL_URL", "http://localhost:8002")
QUERY_URL = os.getenv("QUERY_URL", "http://localhost:8003")


def verify_api_key(x_api_key: Optional[str] = Header(None)) -> str:
    """Verify API key from header"""
    if not x_api_key:
        raise HTTPException(status_code=401, detail="X-API-Key header required")
    
    if x_api_key != config.API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return x_api_key


@app.post("/documents/upload", response_model=DocumentResponse)
async def upload_document(
    file: UploadFile = File(...),
    api_key: str = Depends(verify_api_key)
) -> DocumentResponse:
    """
    Upload and ingest a document.
    
    Args:
        file: Document file to upload
        api_key: API key for authentication
        
    Returns:
        DocumentResponse with document_id and chunk count
    """
    try:
        logger.info("Document upload requested", extra={"document_filename": file.filename})
        
        # Forward to ingestion service
        async with httpx.AsyncClient(timeout=60.0) as client:
            # Read file content
            content = await file.read()
            
            # Forward to ingestion service
            response = await client.post(
                f"{INGESTION_URL}/ingest",
                files={"file": (file.filename, content, file.content_type)},
                timeout=60.0
            )
            response.raise_for_status()
            
            result = response.json()
            logger.info("Document uploaded successfully", extra={
                "document_id": result.get("document_id"),
                "chunks_created": result.get("chunks_created")
            })
            
            return DocumentResponse(**result)
    
    except httpx.HTTPError as e:
        logger.error("Ingestion service error", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Ingestion service error: {str(e)}")
    except Exception as e:
        logger.error("Upload failed", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")


@app.post("/query", response_model=QueryResponse)
async def query(
    request: QueryRequest,
    api_key: str = Depends(verify_api_key)
) -> QueryResponse:
    """
    Process a RAG query.
    
    Args:
        request: Query request
        api_key: API key for authentication
        
    Returns:
        QueryResponse with answer and sources
    """
    try:
        logger.info("Query received", extra={"query": request.query})
        
        # Forward to query service
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                f"{QUERY_URL}/query",
                json=request.model_dump(),
                timeout=60.0
            )
            response.raise_for_status()
            
            result = response.json()
            logger.info("Query processed successfully", extra={
                "chunks_used": result.get("chunks_used"),
                "sources_count": len(result.get("sources", []))
            })
            
            return QueryResponse(**result)
    
    except httpx.HTTPError as e:
        logger.error("Query service error", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Query service error: {str(e)}")
    except Exception as e:
        logger.error("Query failed", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Query failed: {str(e)}")


@app.get("/documents")
async def list_documents(api_key: str = Depends(verify_api_key)):
    """
    List all indexed documents in the vector database.

    Args:
        api_key: API key for authentication

    Returns:
        Dictionary with document count and list of document names
    """
    try:
        logger.info("Listing indexed documents")

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(f"{RETRIEVAL_URL}/documents")
            response.raise_for_status()

            result = response.json()
            logger.info("Documents listed", extra={"count": result.get("count", 0)})

            return result

    except httpx.HTTPError as e:
        logger.error("Retrieval service error", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Retrieval service error: {str(e)}")
    except Exception as e:
        logger.error("Failed to list documents", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Failed to list documents: {str(e)}")


@app.delete("/documents")
async def clear_documents(api_key: str = Depends(verify_api_key)):
    """
    Clear all documents from the vector database.

    Args:
        api_key: API key for authentication

    Returns:
        Dictionary with status and count of deleted documents
    """
    try:
        logger.info("Clearing all indexed documents")

        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.delete(f"{RETRIEVAL_URL}/documents")
            response.raise_for_status()

            result = response.json()
            logger.info("Documents cleared", extra={"deleted_count": result.get("deleted_count", 0)})

            return result

    except httpx.HTTPError as e:
        logger.error("Retrieval service error", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Retrieval service error: {str(e)}")
    except Exception as e:
        logger.error("Failed to clear documents", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Failed to clear documents: {str(e)}")


@app.get("/health")
async def health():
    """Health check endpoint"""
    services_status = {}
    
    # Check ingestion service
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{INGESTION_URL}/health", timeout=5.0)
            services_status["ingestion"] = "healthy" if response.status_code == 200 else "unhealthy"
    except Exception:
        services_status["ingestion"] = "unhealthy"
    
    # Check query service
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{QUERY_URL}/health", timeout=5.0)
            services_status["query"] = "healthy" if response.status_code == 200 else "unhealthy"
    except Exception:
        services_status["query"] = "unhealthy"
    
    overall = "healthy" if all(s == "healthy" for s in services_status.values()) else "degraded"
    
    return {
        "status": overall,
        "services": services_status,
        "service": "api_gateway"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
