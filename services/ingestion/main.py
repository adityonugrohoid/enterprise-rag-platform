"""Ingestion service for processing and storing documents."""
import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
import uuid
import os
import tempfile
from datetime import datetime
from typing import List
import logging

from shared.utils.logging import setup_logging
from shared.utils.pii_detector import PIIDetector
from shared.models.schemas import ChunkMetadata, DataClassification, DocumentResponse
from shared.clients.embedder import Embedder
from shared.clients.chroma_client import ChromaClient
from services.ingestion.parser import DocumentParser
from services.ingestion.chunker import TextChunker

logger = setup_logging("ingestion_service")
app = FastAPI(title="Ingestion Service")

# Initialize components
embedder = Embedder()
chroma_client = ChromaClient()
parser = DocumentParser()
chunker = TextChunker()


@app.post("/ingest", response_model=DocumentResponse)
async def ingest_document(file: UploadFile = File(...)) -> DocumentResponse:
    """
    Ingest a document: parse, chunk, embed, and store.
    
    Args:
        file: Uploaded file
        
    Returns:
        DocumentResponse with document_id and chunk count
    """
    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename required")
    
    doc_id = str(uuid.uuid4())
    logger.info("Starting document ingestion", extra={
        "doc_id": doc_id,
        "document_filename": file.filename
    })
    
    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as tmp_file:
            content = await file.read()
            tmp_file.write(content)
            tmp_path = tmp_file.name
        
        try:
            # Parse document
            text, metadata = parser.parse(tmp_path)
            logger.info("Document parsed", extra={"doc_id": doc_id, "text_length": len(text)})
            
            # Chunk text
            chunks = chunker.chunk(text)
            logger.info("Text chunked", extra={"doc_id": doc_id, "chunk_count": len(chunks)})
            
            # Process chunks: detect PII, create embeddings
            chunk_texts = [chunk["text"] for chunk in chunks]
            embeddings = embedder.embed(chunk_texts)
            
            # Prepare metadata for ChromaDB
            chroma_metadatas = []
            chroma_ids = []
            pii_detected_any = False
            
            for idx, chunk in enumerate(chunks):
                pii_found, pii_types = PIIDetector.detect(chunk["text"])
                if pii_found:
                    pii_detected_any = True
                
                chunk_metadata = ChunkMetadata(
                    document_id=doc_id,
                    filename=file.filename,
                    chunk_index=idx,
                    start_char=chunk["start"],
                    end_char=chunk["end"],
                    ingested_at=datetime.now().isoformat(),
                    pii_detected=pii_found,
                    pii_types=pii_types,
                    data_classification=DataClassification.INTERNAL
                )
                
                # Convert metadata to dict and handle list fields for ChromaDB compatibility
                metadata_dict = chunk_metadata.model_dump()
                
                # Convert all list fields to strings (ChromaDB doesn't support lists in metadata)
                # Convert pii_types list to comma-separated string
                if metadata_dict.get("pii_types") and len(metadata_dict["pii_types"]) > 0:
                    metadata_dict["pii_types"] = ",".join([p.value if hasattr(p, 'value') else str(p) for p in metadata_dict["pii_types"]])
                else:
                    metadata_dict["pii_types"] = ""
                
                # Ensure all values are ChromaDB-compatible (str, int, float, bool, None)
                # Remove any None values and convert complex types
                cleaned_metadata = {}
                for key, value in metadata_dict.items():
                    if value is None:
                        cleaned_metadata[key] = ""
                    elif isinstance(value, (str, int, float, bool)):
                        cleaned_metadata[key] = value
                    elif isinstance(value, list):
                        # Convert lists to comma-separated strings
                        cleaned_metadata[key] = ",".join(str(v) for v in value) if value else ""
                    else:
                        # Convert other types to string
                        cleaned_metadata[key] = str(value)
                
                chroma_metadatas.append(cleaned_metadata)
                chroma_ids.append(f"{doc_id}_chunk_{idx}")
                
                if pii_found:
                    logger.warning("PII detected in chunk", extra={
                        "doc_id": doc_id,
                        "chunk_index": idx,
                        "pii_types": [p.value for p in pii_types]
                    })
            
            # Store in ChromaDB
            chroma_client.add(
                embeddings=embeddings,
                documents=chunk_texts,
                metadatas=chroma_metadatas,
                ids=chroma_ids
            )
            
            logger.info("Document ingested successfully", extra={
                "doc_id": doc_id,
                "chunks_created": len(chunks),
                "pii_detected": pii_detected_any
            })
            
            return DocumentResponse(
                success=True,
                document_id=doc_id,
                chunks_created=len(chunks),
                pii_detected=pii_detected_any
            )
        
        finally:
            # Clean up temp file
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    
    except Exception as e:
        logger.error("Ingestion failed", extra={"doc_id": doc_id, "error": str(e)})
        raise HTTPException(status_code=500, detail=f"Ingestion failed: {str(e)}")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "ingestion"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
