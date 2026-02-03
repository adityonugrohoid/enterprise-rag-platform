"""Prompt templates and context formatting for RAG."""
from typing import List, Dict, Tuple
import tiktoken
import os
import logging

logger = logging.getLogger(__name__)


def get_encoder_for_model(model: str):
    """Get appropriate tokenizer for model"""
    try:
        if "llama" in model.lower():
            return tiktoken.get_encoding("cl100k_base")
        elif "gpt" in model.lower():
            return tiktoken.encoding_for_model(model)
        elif "gemini" in model.lower():
            return tiktoken.get_encoding("cl100k_base")
        else:
            return tiktoken.get_encoding("cl100k_base")
    except Exception:
        # Fallback to cl100k_base if model not found
        return tiktoken.get_encoding("cl100k_base")


def format_context_with_token_budget(
    chunks: List[Dict],
    max_tokens: int = 4000,
    model: str = "llama3.2"
) -> Tuple[str, int]:
    """
    Format context with token budget awareness to prevent overflow.
    
    Args:
        chunks: Retrieved document chunks
        max_tokens: Maximum tokens allowed for context
        model: LLM model name for tokenization
        
    Returns:
        Tuple of (formatted_context, total_tokens)
    """
    encoder = get_encoder_for_model(model)
    context_parts = []
    total_tokens = 0
    
    for chunk in chunks:
        chunk_text = chunk.get("text", "")
        filename = chunk.get("metadata", {}).get("filename", "unknown")
        chunk_formatted = f"[{filename}]: {chunk_text}"
        chunk_tokens = len(encoder.encode(chunk_formatted))
        
        if total_tokens + chunk_tokens > max_tokens:
            break
        
        context_parts.append(chunk_formatted)
        total_tokens += chunk_tokens
    
    return "\n\n".join(context_parts), total_tokens


def build_rag_prompt(query: str, context: str) -> List[Dict[str, str]]:
    """
    Build RAG prompt with context and query.
    
    Args:
        query: User query
        context: Retrieved context from documents
        
    Returns:
        List of messages for LLM
    """
    system_prompt = """You are a helpful assistant that answers questions based on the provided context documents.
    
Rules:
- Only use information from the provided context
- If the context doesn't contain relevant information, say so
- Cite sources using the document filenames
- Be concise and accurate
- If you're unsure, say so rather than guessing"""

    user_prompt = f"""Context documents:
{context}

Question: {query}

Answer the question based on the context above. If the context doesn't contain enough information, say so."""

    return [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
    ]
