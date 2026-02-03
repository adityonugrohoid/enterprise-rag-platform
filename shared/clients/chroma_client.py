"""ChromaDB client for vector storage and retrieval."""
import chromadb
from chromadb.config import Settings
from typing import List, Dict, Any, Optional
import logging
import os

logger = logging.getLogger(__name__)


class ChromaClient:
    """Client for ChromaDB vector database"""
    
    def __init__(self, host: Optional[str] = None):
        """Initialize ChromaDB client"""
        host = host or os.getenv("CHROMA_HOST", "http://localhost:8000")
        logger.info(f"Connecting to ChromaDB at {host}")
        
        # Parse host and port
        host_clean = host.replace("http://", "").replace("https://", "")
        if ":" in host_clean:
            hostname, port_str = host_clean.split(":")
            port = int(port_str)
        else:
            hostname = host_clean
            port = 8000
        
        # Connect to ChromaDB (newer versions use v2 API automatically)
        self.client = chromadb.HttpClient(
            host=hostname,
            port=port,
            settings=Settings(anonymized_telemetry=False)
        )
        
        self.collection = self.client.get_or_create_collection(
            name="documents",
            metadata={"hnsw:space": "cosine"}
        )
        logger.info("ChromaDB client initialized")
    
    def add(
        self,
        embeddings: List[List[float]],
        documents: List[str],
        metadatas: List[Dict[str, Any]],
        ids: List[str]
    ) -> None:
        """Add documents to the collection"""
        self.collection.add(
            embeddings=embeddings,
            documents=documents,
            metadatas=metadatas,
            ids=ids
        )
        logger.info(f"Added {len(documents)} documents to ChromaDB")
    
    def query(
        self,
        query_embeddings: List[List[float]],
        n_results: int = 5
    ) -> Dict[str, Any]:
        """Query the collection for similar documents"""
        results = self.collection.query(
            query_embeddings=query_embeddings,
            n_results=n_results
        )
        return results
    
    def count(self) -> int:
        """Get total number of documents in collection"""
        return self.collection.count()
