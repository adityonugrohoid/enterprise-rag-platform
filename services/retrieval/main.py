"""Retrieval service for vector search."""
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any
import logging

from shared.utils.logging import setup_logging
from shared.clients.embedder import Embedder
from shared.clients.chroma_client import ChromaClient

logger = setup_logging("retrieval_service")
app = FastAPI(title="Retrieval Service")

# Initialize components
embedder = Embedder()
chroma_client = ChromaClient()


class RetrievalRequest(BaseModel):
    """Request for retrieval"""
    query: str
    top_k: int = 5


class RetrievalResponse(BaseModel):
    """Response from retrieval"""
    chunks: List[Dict[str, Any]]
    count: int


@app.post("/retrieve", response_model=RetrievalResponse)
async def retrieve(request: RetrievalRequest) -> RetrievalResponse:
    """
    Retrieve relevant document chunks for a query.
    
    Args:
        request: Retrieval request with query and top_k
        
    Returns:
        RetrievalResponse with relevant chunks
    """
    try:
        logger.info("Retrieving chunks", extra={"query": request.query, "top_k": request.top_k})
        
        # Generate query embedding
        query_embedding = embedder.embed(request.query)
        
        # Query ChromaDB
        results = chroma_client.query(
            query_embeddings=query_embedding,
            n_results=request.top_k
        )
        
        # Format results
        chunks = []
        if results.get("documents") and len(results["documents"]) > 0:
            documents = results["documents"][0]
            metadatas = results.get("metadatas", [[]])[0] if results.get("metadatas") else []
            distances = results.get("distances", [[]])[0] if results.get("distances") else []
            
            for idx, doc in enumerate(documents):
                chunk_data = {
                    "text": doc,
                    "metadata": metadatas[idx] if idx < len(metadatas) else {},
                    "score": 1.0 - distances[idx] if idx < len(distances) else 0.0  # Convert distance to similarity
                }
                chunks.append(chunk_data)
        
        logger.info("Retrieval complete", extra={"chunks_found": len(chunks)})
        
        return RetrievalResponse(
            chunks=chunks,
            count=len(chunks)
        )
    
    except Exception as e:
        logger.error("Retrieval failed", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Retrieval failed: {str(e)}")


@app.get("/documents")
async def list_documents():
    """
    List all indexed documents in the vector database.

    Returns:
        Dictionary with document count and list of document names
    """
    try:
        # Get all documents from collection
        results = chroma_client.collection.get(include=["metadatas"])

        # Extract unique document filenames
        documents = set()
        if results and results.get("metadatas"):
            for meta in results["metadatas"]:
                if meta and "filename" in meta:
                    documents.add(meta["filename"])

        doc_list = sorted(list(documents))
        logger.info("Listed indexed documents", extra={"count": len(doc_list)})

        return {
            "count": len(doc_list),
            "documents": doc_list
        }

    except Exception as e:
        logger.error("Failed to list documents", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Failed to list documents: {str(e)}")


@app.delete("/documents")
async def clear_documents():
    """
    Clear all documents from the vector database.

    Returns:
        Dictionary with status and count of deleted documents
    """
    try:
        # Get current count before deletion
        count = chroma_client.collection.count()

        # Delete the collection and recreate it
        chroma_client.client.delete_collection("documents")
        chroma_client.collection = chroma_client.client.get_or_create_collection(
            name="documents",
            metadata={"hnsw:space": "cosine"}
        )

        logger.info("Cleared all documents from database", extra={"deleted_count": count})

        return {
            "success": True,
            "message": f"Cleared {count} chunks from database",
            "deleted_count": count
        }

    except Exception as e:
        logger.error("Failed to clear documents", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Failed to clear documents: {str(e)}")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "retrieval"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
