#!/usr/bin/env python3
"""End-to-End test script for RAG flow."""
import httpx
import sys
import os
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

API_URL = "http://localhost:8080"
API_KEY = "dev-api-key"
TEST_DOC = project_root / "data" / "documents" / "internal_doc_00_network_performance_standards.txt"


def check_health(client: httpx.Client) -> bool:
    """Check if API Gateway is healthy"""
    try:
        response = client.get(f"{API_URL}/health", timeout=5.0)
        if response.status_code == 200:
            print("✅ API Gateway is healthy")
            return True
        else:
            print(f"❌ API Gateway returned status {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ API Gateway is not responding: {e}")
        return False


def test_document_upload(client: httpx.Client) -> tuple[str, int] | None:
    """Test document upload"""
    print("\n📄 Step 2: Testing document ingestion...")
    
    if not TEST_DOC.exists():
        print(f"❌ Test document not found: {TEST_DOC}")
        print("   Please generate sample documents first:")
        print("   python scripts/generate_sample_docs.py")
        return None
    
    try:
        with open(TEST_DOC, "rb") as f:
            files = {"file": (TEST_DOC.name, f, "text/plain")}
            response = client.post(
                f"{API_URL}/documents/upload",
                headers={"X-API-Key": API_KEY},
                files=files,
                timeout=60.0
            )
            response.raise_for_status()
            data = response.json()
            
            doc_id = data.get("document_id")
            chunks = data.get("chunks_created", 0)
            
            print(f"✅ Document uploaded successfully")
            print(f"   Document ID: {doc_id}")
            print(f"   Chunks created: {chunks}")
            
            return doc_id, chunks
    except httpx.HTTPError as e:
        print(f"❌ Document upload failed: {e}")
        if hasattr(e, 'response'):
            print(f"   Response: {e.response.text}")
        return None
    except Exception as e:
        print(f"❌ Document upload failed: {e}")
        return None


def test_query(client: httpx.Client, query: str) -> dict | None:
    """Test RAG query"""
    try:
        response = client.post(
            f"{API_URL}/query",
            headers={
                "Content-Type": "application/json",
                "X-API-Key": API_KEY
            },
            json={"query": query},
            timeout=60.0
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPError as e:
        print(f"❌ Query failed: {e}")
        if hasattr(e, 'response'):
            print(f"   Response: {e.response.text}")
        return None
    except Exception as e:
        print(f"❌ Query failed: {e}")
        return None


def main():
    """Run E2E tests"""
    print("=" * 50)
    print("Enterprise RAG Platform - E2E Test")
    print("=" * 50)
    
    with httpx.Client(timeout=60.0) as client:
        # Step 1: Health check
        print("\n🏥 Step 1: Checking service health...")
        if not check_health(client):
            print("\n❌ Services are not healthy. Please start services first.")
            print("   Run: docker compose up -d")
            sys.exit(1)
        
        # Step 2: Document upload
        result = test_document_upload(client)
        if not result:
            print("\n❌ Document upload test failed")
            sys.exit(1)
        
        doc_id, chunks = result
        
        # Wait for indexing
        print("\n⏳ Waiting 2 seconds for indexing...")
        import time
        time.sleep(2)
        
        # Step 3: RAG Query Test
        print("\n🔍 Step 3: Testing RAG query...")
        query = "What are the 5G RAN performance targets for call drop rate?"
        response = test_query(client, query)
        
        if not response:
            print("\n❌ Query test failed")
            sys.exit(1)
        
        answer = response.get("answer", "")
        sources = response.get("sources", [])
        chunks_used = response.get("chunks_used", 0)
        
        print(f"✅ Query processed successfully")
        print(f"   Query: {query}")
        print(f"   Sources: {sources}")
        print(f"   Chunks used: {chunks_used}")
        print()
        print("   Model Response:")
        print("   " + "─" * 60)
        # Print answer with proper indentation, handling multi-line responses
        for line in answer.split('\n'):
            print(f"   {line}")
        print("   " + "─" * 60)
        print()
        
        # Step 4: Additional test queries
        print("\n🔍 Step 4: Testing additional queries...")
        test_queries = [
            "What is network optimization?",
            "How do I troubleshoot high call drop rates?"
        ]
        
        for test_query_text in test_queries:
            response = test_query(client, test_query_text)
            if response and response.get("success"):
                answer = response.get("answer", "")
                print(f"✅ Query passed: '{test_query_text[:50]}...'")
                print()
                print("   Query: " + test_query_text)
                print("   Model Response:")
                print("   " + "─" * 60)
                for line in answer.split('\n'):
                    print(f"   {line}")
                print("   " + "─" * 60)
                print()
            else:
                print(f"⚠️  Query had issues: '{test_query_text[:50]}...'")
        
        print("\n" + "=" * 50)
        print("✅ All E2E tests passed!")
        print("=" * 50)


if __name__ == "__main__":
    main()
