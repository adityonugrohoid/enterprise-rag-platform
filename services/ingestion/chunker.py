"""Text chunking utilities."""
from typing import List, Dict
import logging

logger = logging.getLogger(__name__)


class TextChunker:
    """Chunk text into smaller pieces for embedding"""
    
    def __init__(self, chunk_size: int = 512, chunk_overlap: int = 50):
        """
        Initialize chunker.
        
        Args:
            chunk_size: Target chunk size in tokens (approximate)
            chunk_overlap: Overlap between chunks in tokens
        """
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
    
    def chunk(self, text: str) -> List[Dict[str, any]]:
        """
        Split text into chunks.
        
        Args:
            text: Text to chunk
            
        Returns:
            List of chunk dictionaries with 'text', 'start', 'end' keys
        """
        # Simple sentence-based chunking
        sentences = self._split_sentences(text)
        chunks = []
        current_chunk = []
        current_length = 0
        start_char = 0
        
        for sentence in sentences:
            sentence_length = len(sentence.split())  # Approximate token count
            
            if current_length + sentence_length > self.chunk_size and current_chunk:
                # Save current chunk
                chunk_text = " ".join(current_chunk)
                chunks.append({
                    "text": chunk_text,
                    "start": start_char,
                    "end": start_char + len(chunk_text)
                })
                
                # Start new chunk with overlap
                overlap_sentences = self._get_overlap_sentences(current_chunk)
                current_chunk = overlap_sentences + [sentence]
                current_length = sum(len(s.split()) for s in current_chunk)
                start_char = chunks[-1]["end"] - len(" ".join(overlap_sentences))
            else:
                current_chunk.append(sentence)
                current_length += sentence_length
        
        # Add final chunk
        if current_chunk:
            chunk_text = " ".join(current_chunk)
            chunks.append({
                "text": chunk_text,
                "start": start_char,
                "end": start_char + len(chunk_text)
            })
        
        logger.info(f"Created {len(chunks)} chunks from text")
        return chunks
    
    def _split_sentences(self, text: str) -> List[str]:
        """Split text into sentences"""
        import re
        # Simple sentence splitting
        sentences = re.split(r'(?<=[.!?])\s+', text)
        return [s.strip() for s in sentences if s.strip()]
    
    def _get_overlap_sentences(self, sentences: List[str]) -> List[str]:
        """Get last N sentences for overlap"""
        overlap_count = max(1, len(sentences) // 4)  # ~25% overlap
        return sentences[-overlap_count:] if len(sentences) > overlap_count else []
