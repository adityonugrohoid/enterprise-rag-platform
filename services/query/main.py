"""Query service for RAG queries."""
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from fastapi import FastAPI, HTTPException
import httpx
import os
import logging
from typing import List

from shared.utils.logging import setup_logging
from shared.utils.config import Config
from shared.clients.universal_llm_client import UniversalLLMClient
from shared.models.schemas import QueryRequest, QueryResponse
from services.query.prompts import build_rag_prompt, format_context_with_token_budget

logger = setup_logging("query_service")
app = FastAPI(title="Query Service")

# Initialize components
config = Config.from_env()
llm_client = UniversalLLMClient(
    provider=config.LLM_PROVIDER,
    model=config.LLM_MODEL,
    host=config.OLLAMA_HOST
)

# Service URLs
RETRIEVAL_URL = os.getenv("RETRIEVAL_URL", "http://localhost:8002")


@app.post("/query", response_model=QueryResponse)
async def query(request: QueryRequest) -> QueryResponse:
    """
    Process a RAG query: retrieve context and generate answer.
    
    Args:
        request: Query request
        
    Returns:
        QueryResponse with answer and sources
    """
    try:
        logger.info("Processing query", extra={"query": request.query})
        
        # Step 1: Retrieve relevant chunks (use top_k=3 for faster CPU inference)
        async with httpx.AsyncClient(timeout=30.0) as client:
            retrieval_response = await client.post(
                f"{RETRIEVAL_URL}/retrieve",
                json={"query": request.query, "top_k": 3}
            )
            retrieval_response.raise_for_status()
            retrieval_data = retrieval_response.json()
        
        chunks = retrieval_data.get("chunks", [])
        if not chunks:
            return QueryResponse(
                success=True,
                answer="I couldn't find any relevant information in the documents to answer your question.",
                sources=[],
                chunks_used=0
            )
        
        logger.info("Retrieved chunks", extra={"chunk_count": len(chunks)})
        
        # Step 2: Format context with token budget (reduced for faster CPU inference)
        context, token_count = format_context_with_token_budget(
            chunks=chunks,
            max_tokens=2000,
            model=config.LLM_MODEL
        )
        logger.info("Context formatted", extra={"token_count": token_count})
        
        # Step 3: Build prompt
        messages = build_rag_prompt(request.query, context)
        
        # Step 4: Generate answer
        answer = llm_client.chat(
            messages=messages,
            temperature=0.2,
            max_tokens=1024
        )
        
        # Step 5: Extract sources
        sources = list(set([
            chunk.get("metadata", {}).get("filename", "unknown")
            for chunk in chunks
        ]))
        
        logger.info("Query processed successfully", extra={
            "chunks_used": len(chunks),
            "sources_count": len(sources)
        })
        
        return QueryResponse(
            success=True,
            answer=answer,
            sources=sources,
            chunks_used=len(chunks)
        )
    
    except httpx.HTTPError as e:
        logger.error("HTTP error in query", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Retrieval service error: {str(e)}")
    except Exception as e:
        logger.error("Query failed", extra={"error": str(e)})
        raise HTTPException(status_code=500, detail=f"Query failed: {str(e)}")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "query"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
