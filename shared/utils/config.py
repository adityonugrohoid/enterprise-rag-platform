"""Configuration management."""
import os
from pydantic import BaseModel


class Config(BaseModel):
    """Application configuration"""
    # Environment
    ENVIRONMENT: str = "local"  # local|production
    
    # API
    API_KEY: str
    JWT_SECRET_KEY: str
    
    # LLM
    LLM_PROVIDER: str = "ollama"  # ollama|openai|anthropic|vertex
    LLM_MODEL: str = "llama3.2:3b"
    OLLAMA_HOST: str = "http://localhost:11434"
    
    # Vector Store
    CHROMA_HOST: str = "http://localhost:8000"
    
    # MinIO/Cloud Storage
    MINIO_ENDPOINT: str = "minio:9000"
    MINIO_ROOT_USER: str
    MINIO_ROOT_PASSWORD: str
    
    # Redis (optional)
    REDIS_HOST: str = "redis"
    REDIS_PORT: int = 6379
    
    @classmethod
    def from_env(cls):
        """Load configuration from environment variables"""
        return cls(
            ENVIRONMENT=os.getenv("ENVIRONMENT", "local"),
            API_KEY=os.getenv("API_KEY", "dev-api-key"),
            JWT_SECRET_KEY=os.getenv("JWT_SECRET_KEY", "change-this"),
            LLM_PROVIDER=os.getenv("LLM_PROVIDER", "ollama"),
            LLM_MODEL=os.getenv("LLM_MODEL", "llama3.2:3b"),
            OLLAMA_HOST=os.getenv("OLLAMA_HOST", "http://localhost:11434"),
            CHROMA_HOST=os.getenv("CHROMA_HOST", "http://localhost:8000"),
            MINIO_ENDPOINT=os.getenv("MINIO_ENDPOINT", "minio:9000"),
            MINIO_ROOT_USER=os.getenv("MINIO_ROOT_USER", "minioadmin"),
            MINIO_ROOT_PASSWORD=os.getenv("MINIO_ROOT_PASSWORD", "minioadmin"),
            REDIS_HOST=os.getenv("REDIS_HOST", "redis"),
            REDIS_PORT=int(os.getenv("REDIS_PORT", "6379"))
        )
