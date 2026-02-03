"""Data models and schemas for the RAG platform."""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Optional, List, Any
from datetime import datetime


class DataClassification(str, Enum):
    """Data classification levels for compliance"""
    PUBLIC = "public"
    INTERNAL = "internal"
    CONFIDENTIAL = "confidential"
    RESTRICTED = "restricted"


class PIIType(str, Enum):
    """Types of PII that can be detected"""
    EMAIL = "email"
    PHONE = "phone"
    SSN = "ssn"
    CREDIT_CARD = "credit_card"
    ADDRESS = "address"
    NAME = "name"


class ChunkMetadata(BaseModel):
    """Enhanced metadata for document chunks"""
    document_id: str
    filename: str
    chunk_index: int
    start_char: int
    end_char: int
    ingested_at: str
    
    # Security & Compliance
    data_classification: DataClassification = DataClassification.INTERNAL
    pii_detected: bool = False
    pii_types: List[PIIType] = []
    retention_days: int = 365
    
    # Performance metadata
    embedding_time_ms: Optional[float] = None
    chunk_size_tokens: Optional[int] = None


class APIResponse(BaseModel):
    """Standard API response format"""
    success: bool
    data: Optional[Any] = None
    error: Optional[str] = None
    timestamp: str = Field(
        default_factory=lambda: datetime.now().isoformat()
    )


class DocumentResponse(BaseModel):
    """Response for document upload"""
    success: bool
    document_id: str
    chunks_created: int
    pii_detected: bool = False


class QueryRequest(BaseModel):
    """Request model for RAG queries"""
    query: str


class QueryResponse(BaseModel):
    """Response model for RAG queries"""
    success: bool
    answer: str
    sources: List[str] = []
    chunks_used: int = 0
