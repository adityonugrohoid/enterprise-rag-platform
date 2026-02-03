"""Document parser for various file formats."""
import os
from typing import Tuple, Dict
import logging

logger = logging.getLogger(__name__)


class DocumentParser:
    """Parser for various document formats"""
    
    def parse(self, file_path: str) -> Tuple[str, Dict[str, str]]:
        """
        Parse a document file.
        
        Args:
            file_path: Path to the document file
            
        Returns:
            Tuple of (text_content, metadata)
        """
        if not os.path.exists(file_path):
            raise ValueError(f"File not found: {file_path}")
        
        filename = os.path.basename(file_path)
        ext = os.path.splitext(filename)[1].lower()
        
        if ext == ".txt":
            return self._parse_txt(file_path)
        elif ext == ".pdf":
            return self._parse_pdf(file_path)
        elif ext in [".doc", ".docx"]:
            return self._parse_docx(file_path)
        else:
            raise ValueError(f"Unsupported file format: {ext}")
    
    def _parse_txt(self, file_path: str) -> Tuple[str, Dict[str, str]]:
        """Parse plain text file"""
        with open(file_path, "r", encoding="utf-8") as f:
            text = f.read()
        
        metadata = {
            "filename": os.path.basename(file_path),
            "format": "txt"
        }
        return text, metadata
    
    def _parse_pdf(self, file_path: str) -> Tuple[str, Dict[str, str]]:
        """Parse PDF file"""
        try:
            import fitz  # PyMuPDF
            doc = fitz.open(file_path)
            text = "\n".join([page.get_text() for page in doc])
            doc.close()
            
            metadata = {
                "filename": os.path.basename(file_path),
                "format": "pdf"
            }
            return text, metadata
        except ImportError:
            raise ImportError("PyMuPDF is required for PDF parsing")
    
    def _parse_docx(self, file_path: str) -> Tuple[str, Dict[str, str]]:
        """Parse DOCX file"""
        try:
            from docx import Document
            doc = Document(file_path)
            text = "\n".join([para.text for para in doc.paragraphs])
            
            metadata = {
                "filename": os.path.basename(file_path),
                "format": "docx"
            }
            return text, metadata
        except ImportError:
            raise ImportError("python-docx is required for DOCX parsing")
