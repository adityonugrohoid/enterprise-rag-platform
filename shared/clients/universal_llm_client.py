"""Universal LLM client supporting multiple providers."""
from typing import Optional, Literal
from openai import OpenAI
import os
import logging

logger = logging.getLogger(__name__)

LLMProvider = Literal["ollama", "openai", "azure", "anthropic", "vertex", "bedrock"]


class UniversalLLMClient:
    """Provider-agnostic LLM client following OpenAI standards"""
    
    def __init__(
        self, 
        provider: LLMProvider = "ollama",
        model: Optional[str] = None,
        **kwargs
    ):
        self.provider = provider
        
        if provider == "ollama":
            host = kwargs.get("host", os.getenv("OLLAMA_HOST", "http://localhost:11434"))
            # Use httpx directly for Ollama to avoid OpenAI client compatibility issues
            import httpx
            self._ollama_host = host
            self._use_httpx = True
            self.client = None  # Will use httpx instead
            self.model = model or os.getenv("LLM_MODEL", "llama3.1:8b")
            
        elif provider == "openai":
            self.client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
            self.model = model or "gpt-4o-mini"
            
        elif provider == "azure":
            from openai import AzureOpenAI
            self.client = AzureOpenAI(
                azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
                api_key=os.getenv("AZURE_OPENAI_KEY"),
                api_version="2024-02-01"
            )
            self.model = model or "gpt-4"
            
        elif provider == "anthropic":
            import anthropic
            self.client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
            self.model = model or "claude-3-5-sonnet-20241022"
            
        elif provider == "vertex":
            # GCP Vertex AI with Gemini models
            import vertexai
            from vertexai.generative_models import GenerativeModel

            project_id = os.getenv("GCP_PROJECT_ID")
            location = os.getenv("GCP_LOCATION", "asia-southeast1")

            if not project_id:
                raise ValueError("GCP_PROJECT_ID environment variable is required for Vertex AI")

            vertexai.init(project=project_id, location=location)
            self.model = model or os.getenv("VERTEX_MODEL", "gemini-2.0-flash-001")
            self.client = GenerativeModel(self.model)

        elif provider == "bedrock":
            # Amazon Bedrock - uses boto3
            import boto3
            self.client = boto3.client(
                "bedrock-runtime",
                region_name=os.getenv("AWS_REGION", "ap-southeast-1")
            )
            # Default to Amazon Nova Micro via APAC inference profile
            # Nova models require inference profile IDs, not model IDs directly
            self.model = model or os.getenv("BEDROCK_MODEL", "apac.amazon.nova-micro-v1:0")

        logger.info(f"Initialized LLM client: {provider} with model {self.model}")
    
    def chat(
        self,
        messages: list[dict],
        temperature: float = 0.2,
        max_tokens: int = 1024,
        **kwargs
    ) -> str:
        """Unified chat interface across providers"""
        
        if self.provider == "ollama" and hasattr(self, "_use_httpx") and self._use_httpx:
            # Use httpx directly for Ollama
            import httpx
            response = httpx.post(
                f"{self._ollama_host}/v1/chat/completions",
                json={
                    "model": self.model,
                    "messages": messages,
                    "temperature": temperature,
                    "max_tokens": max_tokens
                },
                timeout=300.0  # 5 minutes for CPU inference with large context
            )
            response.raise_for_status()
            return response.json()["choices"][0]["message"]["content"]
        
        if self.provider == "anthropic":
            # Anthropic uses different message format
            response = self.client.messages.create(
                model=self.model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens
            )
            return response.content[0].text

        elif self.provider == "bedrock":
            # Amazon Bedrock - use Converse API for unified interface
            import json

            # Convert messages to Bedrock format
            bedrock_messages = []
            system_prompt = None

            for msg in messages:
                if msg["role"] == "system":
                    system_prompt = msg["content"]
                else:
                    bedrock_messages.append({
                        "role": msg["role"],
                        "content": [{"text": msg["content"]}]
                    })

            # Build request
            request_params = {
                "modelId": self.model,
                "messages": bedrock_messages,
                "inferenceConfig": {
                    "temperature": temperature,
                    "maxTokens": max_tokens
                }
            }

            if system_prompt:
                request_params["system"] = [{"text": system_prompt}]

            response = self.client.converse(**request_params)
            return response["output"]["message"]["content"][0]["text"]

        elif self.provider == "vertex":
            from vertexai.generative_models import GenerationConfig, Content, Part

            # Convert messages to Gemini format
            system_instruction = None
            gemini_contents = []

            for msg in messages:
                if msg["role"] == "system":
                    system_instruction = msg["content"]
                elif msg["role"] == "user":
                    gemini_contents.append(Content(role="user", parts=[Part.from_text(msg["content"])]))
                elif msg["role"] == "assistant":
                    gemini_contents.append(Content(role="model", parts=[Part.from_text(msg["content"])]))

            # Create a model with system instruction if provided
            if system_instruction:
                from vertexai.generative_models import GenerativeModel
                model_with_system = GenerativeModel(
                    self.model,
                    system_instruction=system_instruction
                )
                response = model_with_system.generate_content(
                    gemini_contents,
                    generation_config=GenerationConfig(
                        temperature=temperature,
                        max_output_tokens=max_tokens
                    )
                )
            else:
                response = self.client.generate_content(
                    gemini_contents,
                    generation_config=GenerationConfig(
                        temperature=temperature,
                        max_output_tokens=max_tokens
                    )
                )

            return response.text
        
        else:  # OpenAI-compatible (ollama, openai, azure)
            response = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                **kwargs
            )
            return response.choices[0].message.content
