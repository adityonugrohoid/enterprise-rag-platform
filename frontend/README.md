# Streamlit UI for Enterprise RAG Platform

A ChatGPT/Claude-style web interface for the Enterprise RAG Platform, featuring dual response comparison between direct LLM and RAG-enhanced queries.

## Features

### 🎨 User Interface
- Clean, centered chat input box inspired by ChatGPT/Claude/Gemini
- Side-by-side dual response panels for easy comparison
- Responsive design with wide layout for optimal viewing
- Color-coded response containers (blue for direct LLM, green for RAG)

### 📚 Document Management
- **Sidebar document selector** with multiselect dropdown
- Automatic scanning of `data/documents/` directory
- Support for `.txt`, `.pdf`, and `.docx` files
- Batch ingestion of multiple documents at once
- Real-time ingestion progress tracking
- Ingestion status tracking (shows which documents are currently loaded)

### 🔄 Dual Response System
**Left Panel: Direct LLM**
- Pure Ollama response without any document context
- Shows model name and response time
- Useful for baseline comparison

**Right Panel: RAG-Enhanced**
- Full RAG pipeline with document retrieval
- Displays source documents used
- Shows number of chunks retrieved
- Includes response time for performance comparison

### 📊 Service Monitoring
- Real-time health check for API Gateway and Ollama
- Visual status indicators (green/red)
- Warnings when services are unavailable

## File Structure

```
frontend/
├── __init__.py          # Package initialization
├── app.py               # Main Streamlit application
├── config.py            # Configuration and environment variables
├── utils.py             # Helper functions for API calls
└── README.md            # This file
```

## Configuration

The UI uses environment variables for configuration (via `config.py`):

- `API_GATEWAY_URL`: API Gateway endpoint (default: `http://localhost:8080`)
- `OLLAMA_HOST`: Ollama server endpoint (default: `http://localhost:11434`)
- `API_KEY`: API authentication key (default: `dev-api-key`)
- `LLM_MODEL`: Model to use (default: `llama3.2:3b`)

## Running the UI

### Quick Start

```bash
# From project root
bash scripts/start_ui.sh
```

The script will:
1. Check for virtual environment
2. Install dependencies if needed
3. Check backend service availability
4. Launch Streamlit on `http://localhost:8501`

### Manual Start

```bash
# Activate virtual environment
source .venv/bin/activate

# Navigate to frontend directory
cd frontend

# Run Streamlit
streamlit run app.py --server.port 8501 --server.address localhost
```

## Usage Guide

### 1. Check Service Status
- Look at the sidebar "Service Status" section
- Ensure both API Gateway and Ollama show "🟢 Healthy"
- If services are unhealthy, start backend services first:
  ```bash
  bash scripts/start_services.sh
  ```

### 2. Ingest Documents
- View available documents in the "Available Documents" section
- Select one or more documents from the multiselect dropdown
- Click "🚀 Ingest Selected Documents"
- Wait for ingestion to complete (progress bar will show status)
- Successfully ingested documents will be listed in the "ingested documents" expander

### 3. Submit Queries
- Enter your question in the centered input box
- Click "🚀 Ask Both Systems" or press Enter
- Wait for both panels to populate with responses
- Compare the direct LLM response (left) with the RAG-enhanced response (right)

### 4. Analyze Results
- Review both responses
- Check the metadata section under each response:
  - **Direct LLM**: Model name and response time
  - **RAG-Enhanced**: Sources used, chunks retrieved, response time
- Note the differences in accuracy and detail

## Key Components

### `config.py`
- Project paths and directory locations
- API endpoint configuration
- Default values and environment variable handling
- Supported file extension definitions

### `utils.py`
- `scan_documents()`: Scans document directory for files
- `upload_document()`: Uploads a document to ingestion service
- `query_with_rag()`: Queries the RAG system via API Gateway
- `query_direct_llm()`: Queries Ollama directly without RAG
- `check_services_health()`: Checks backend service availability

### `app.py`
- Main Streamlit application
- UI layout and styling
- Session state management
- Form handling and response display
- Real-time service monitoring

## Customization

### Styling
The UI uses custom CSS (in `app.py`) for styling. You can modify:
- Response container colors and borders
- Header and text alignment
- Status indicator colors
- Metadata formatting

### Layout
Adjust the layout by modifying:
- Column ratios in `st.columns()`
- Sidebar width (via Streamlit config)
- Response container styling

### Functionality
Extend the UI by adding:
- Chat history persistence
- Export functionality for responses
- Advanced filtering for documents
- Performance metrics visualization
- Multi-turn conversation support

## Troubleshooting

### Services Not Healthy
**Issue**: Red status indicators for services
**Solution**: Start backend services:
```bash
bash scripts/start_services.sh
```

### No Documents Found
**Issue**: "No documents found" message
**Solution**: Add documents to `data/documents/` directory

### Ingestion Fails
**Issue**: Error messages during ingestion
**Solution**: 
- Check API Gateway is running
- Verify API key is correct
- Check file format is supported (.txt, .pdf, .docx)
- Review logs in `logs/ingestion.log`

### Import Errors
**Issue**: Module not found errors
**Solution**: Install dependencies:
```bash
pip install -r requirements.txt
```

### Port Already in Use
**Issue**: Port 8501 already in use
**Solution**: Kill the existing Streamlit process or use a different port:
```bash
streamlit run app.py --server.port 8502
```

## Performance Tips

1. **Batch Ingestion**: Ingest multiple documents at once rather than one at a time
2. **Clear Status**: Use the "Clear Ingestion Status" button to reset tracking
3. **Service Health**: Check service health before submitting queries
4. **Response Time**: Compare response times to understand performance characteristics

## Future Enhancements

Potential improvements for the UI:
- [ ] Chat history with conversation context
- [ ] Export responses to file (JSON, Markdown)
- [ ] Advanced query parameters (temperature, top_k, etc.)
- [ ] Document preview and metadata display
- [ ] Response comparison scoring
- [ ] Streaming responses for real-time display
- [ ] User feedback collection
- [ ] Query history and favorites
- [ ] Multi-language support
- [ ] Dark mode toggle

## Contributing

When adding new features:
1. Update `config.py` for new configuration options
2. Add helper functions to `utils.py`
3. Update UI components in `app.py`
4. Test thoroughly with backend services
5. Update this README with new features

## License

Part of the Enterprise RAG Platform project.
