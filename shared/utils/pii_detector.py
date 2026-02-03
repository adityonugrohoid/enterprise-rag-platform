"""PII detection utilities."""
import re
from typing import List, Tuple
from shared.models.schemas import PIIType


class PIIDetector:
    """Simple rule-based PII detector for compliance"""
    
    # Regex patterns
    EMAIL_PATTERN = r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
    PHONE_PATTERN = r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b'
    SSN_PATTERN = r'\b\d{3}-\d{2}-\d{4}\b'
    CREDIT_CARD_PATTERN = r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b'
    
    @staticmethod
    def detect(text: str) -> Tuple[bool, List[PIIType]]:
        """
        Detect PII in text.
        
        Args:
            text: Text to analyze
            
        Returns:
            Tuple of (pii_found, list_of_pii_types)
        """
        pii_types = []
        
        if re.search(PIIDetector.EMAIL_PATTERN, text):
            pii_types.append(PIIType.EMAIL)
        if re.search(PIIDetector.PHONE_PATTERN, text):
            pii_types.append(PIIType.PHONE)
        if re.search(PIIDetector.SSN_PATTERN, text):
            pii_types.append(PIIType.SSN)
        if re.search(PIIDetector.CREDIT_CARD_PATTERN, text):
            pii_types.append(PIIType.CREDIT_CARD)
        
        return len(pii_types) > 0, pii_types
    
    @staticmethod
    def redact(text: str) -> str:
        """Redact PII from text"""
        text = re.sub(PIIDetector.EMAIL_PATTERN, "[EMAIL]", text)
        text = re.sub(PIIDetector.PHONE_PATTERN, "[PHONE]", text)
        text = re.sub(PIIDetector.SSN_PATTERN, "[SSN]", text)
        text = re.sub(PIIDetector.CREDIT_CARD_PATTERN, "[CC]", text)
        return text
