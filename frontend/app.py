"""Streamlit UI for Enterprise RAG Platform."""
import streamlit as st
import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root / "frontend"))

from config import PAGE_TITLE, PAGE_ICON, LAYOUT, PREDEFINED_QUESTIONS, USE_CASES, get_questions_by_use_case
from utils import (
    scan_documents,
    scan_documents_flat,
    upload_document,
    query_with_rag,
    query_direct_llm,
    check_services_health,
    get_indexed_document_count,
    clear_indexed_documents
)

# Page configuration
st.set_page_config(
    page_title=PAGE_TITLE,
    page_icon=PAGE_ICON,
    layout=LAYOUT,
    initial_sidebar_state="expanded"
)

# Custom CSS for better styling
st.markdown("""
<style>
    .main-header {
        text-align: center;
        padding: 2rem 0;
    }
    .submitted-query {
        background-color: #e8f4f8;
        border-left: 4px solid #1f77b4;
        padding: 1rem 1.5rem;
        border-radius: 0.5rem;
        margin: 1.5rem 0;
        color: #1f1f1f;
        font-size: 1.1rem;
        font-weight: 500;
    }
    .submitted-query-label {
        font-size: 0.85rem;
        color: #555;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        margin-bottom: 0.5rem;
    }
    .response-container {
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 1rem 0;
        color: #1f1f1f;
    }
    .direct-llm {
        background-color: #f0f2f6;
        border-left: 4px solid #4A90E2;
        color: #1f1f1f;
    }
    .rag-enhanced {
        background-color: #f0f2f6;
        border-left: 4px solid #50C878;
        color: #1f1f1f;
    }
    .metadata {
        font-size: 0.85rem;
        color: #555;
        margin-top: 1rem;
        padding-top: 1rem;
        border-top: 1px solid #ddd;
    }
    .status-indicator {
        display: inline-block;
        width: 10px;
        height: 10px;
        border-radius: 50%;
        margin-right: 5px;
    }
    .status-healthy {
        background-color: #50C878;
    }
    .status-unhealthy {
        background-color: #E74C3C;
    }
</style>
""", unsafe_allow_html=True)

# Initialize session state
if "ingested_docs" not in st.session_state:
    st.session_state.ingested_docs = set()
if "query_history" not in st.session_state:
    st.session_state.query_history = []
if "last_query" not in st.session_state:
    st.session_state.last_query = None
if "selected_question" not in st.session_state:
    st.session_state.selected_question = ""
if "indexed_count" not in st.session_state:
    st.session_state.indexed_count = 0
if "selected_use_case" not in st.session_state:
    st.session_state.selected_use_case = "all"

# Sidebar - Document Management
with st.sidebar:
    st.header("📚 Document Management")

    # Service health check
    st.subheader("Service Status")
    health = check_services_health()

    api_status = "🟢 Healthy" if health["api_gateway"] else "🔴 Unhealthy"
    ollama_status = "🟢 Healthy" if health["ollama"] else "🔴 Unhealthy"

    st.write(f"**API Gateway:** {api_status}")
    st.write(f"**Ollama:** {ollama_status}")

    if not all(health.values()):
        st.warning("⚠️ Some services are not available. Please start all backend services.")

    st.divider()

    # Use Case / Field Selector
    st.subheader("🎯 Select Use Case")

    # Build options list
    use_case_options = ["All Categories"]
    use_case_keys = ["all"]
    for key, info in USE_CASES.items():
        use_case_options.append(f"{info['icon']} {info['label']}")
        use_case_keys.append(key)

    selected_idx = st.selectbox(
        "Filter by use case:",
        range(len(use_case_options)),
        format_func=lambda i: use_case_options[i],
        key="use_case_selector",
        help="Select a use case to filter available documents"
    )
    st.session_state.selected_use_case = use_case_keys[selected_idx]

    # Show description for selected use case
    if st.session_state.selected_use_case != "all":
        use_case_info = USE_CASES[st.session_state.selected_use_case]
        st.caption(f"*{use_case_info['description']}*")

    st.divider()

    # Show indexed documents in database
    st.subheader("📊 Indexed Documents")
    st.session_state.indexed_count, indexed_docs = get_indexed_document_count()

    if st.session_state.indexed_count > 0:
        st.success(f"✅ {st.session_state.indexed_count} document(s) in vector database")
        if indexed_docs:
            with st.expander("View indexed documents"):
                for doc in indexed_docs:
                    st.write(f"• {doc}")
        # Update session state to reflect actual indexed docs
        st.session_state.ingested_docs = set(indexed_docs) if indexed_docs else set()
    else:
        st.warning("⚠️ No documents indexed yet")

    st.divider()

    # Document selection
    st.subheader("📁 Available Documents")
    docs_by_category = scan_documents()

    # Filter by selected use case
    if st.session_state.selected_use_case == "all":
        filtered_categories = docs_by_category
    else:
        filtered_categories = {
            k: v for k, v in docs_by_category.items()
            if k == st.session_state.selected_use_case
        }

    if not filtered_categories:
        st.info("No documents found for selected use case")
    else:
        # Count total documents
        total_docs = sum(len(docs) for docs in filtered_categories.values())
        st.write(f"Found **{total_docs}** document(s) in **{len(filtered_categories)}** category(ies)")

        # Build flat list with category prefix for selection
        available_docs = []
        for category, docs in sorted(filtered_categories.items()):
            for doc in docs:
                available_docs.append(f"{category}/{doc}")

        # Filter out already indexed documents
        not_indexed = [d for d in available_docs if d not in st.session_state.ingested_docs]

        if not_indexed:
            # Multiselect for documents not yet indexed
            selected_docs = st.multiselect(
                "Select documents to ingest:",
                options=not_indexed,
                format_func=lambda x: f"{USE_CASES.get(x.split('/')[0], {}).get('icon', '📄')} {x.split('/')[-1]}",
                help="Choose one or more documents to ingest into the RAG system"
            )
        else:
            selected_docs = []
            st.info("✅ All available documents are already indexed")

        # Ingest button
        if st.button("🚀 Ingest Selected Documents", disabled=not selected_docs or not health["api_gateway"]):
            if selected_docs:
                with st.spinner("Ingesting documents..."):
                    success_count = 0
                    error_count = 0

                    progress_bar = st.progress(0)
                    status_text = st.empty()

                    for i, doc in enumerate(selected_docs):
                        doc_name = doc.split('/')[-1]
                        status_text.text(f"Processing {doc_name}...")
                        success, message, data = upload_document(doc)

                        if success:
                            success_count += 1
                            st.session_state.ingested_docs.add(doc)
                            chunks = data.get("chunks_created", 0)
                            st.success(f"✅ {doc_name}: {chunks} chunks created")
                        else:
                            error_count += 1
                            st.error(f"❌ {doc_name}: {message}")

                        progress_bar.progress((i + 1) / len(selected_docs))

                    status_text.empty()
                    progress_bar.empty()

                    if success_count > 0:
                        st.success(f"Successfully ingested {success_count} document(s)")
                    if error_count > 0:
                        st.warning(f"Failed to ingest {error_count} document(s)")

    st.divider()

    # Clear database
    st.subheader("🗑️ Database Management")
    if st.session_state.indexed_count > 0:
        st.warning(f"⚠️ This will permanently delete all {st.session_state.indexed_count} indexed documents")
        if st.button("🗑️ Clear Vector Database", type="secondary"):
            with st.spinner("Clearing database..."):
                success, message, deleted = clear_indexed_documents()
                if success:
                    st.session_state.ingested_docs.clear()
                    st.session_state.indexed_count = 0
                    st.success(f"✅ {message}")
                    st.rerun()
                else:
                    st.error(f"❌ {message}")
    else:
        st.info("Database is empty")

    # Information
    with st.expander("ℹ️ How to use"):
        st.markdown("""
        **Steps:**
        1. Check that services are healthy
        2. Select a use case to filter documents
        3. Select documents to ingest
        4. Click "Ingest Selected Documents"
        5. Enter your query in the main area
        6. Compare responses from both systems

        **Left Panel:** Direct LLM (no context)
        **Right Panel:** RAG-enhanced (with document context)
        """)

# Main content area
st.markdown("<h1 class='main-header'>🤖 Enterprise RAG Platform</h1>", unsafe_allow_html=True)
st.markdown("<p style='text-align: center; color: #666;'>Compare responses from direct LLM vs RAG-enhanced system</p>", unsafe_allow_html=True)

# Check if services are available
if not all(health.values()):
    st.error("⚠️ Backend services are not running. Please start the services with: `bash scripts/start_services.sh`")
    st.stop()

# Check if documents are ingested
if st.session_state.indexed_count == 0:
    st.info("💡 Please ingest documents from the sidebar to get started with RAG queries.")

# Query input
st.divider()

# Get questions filtered by selected use case
filtered_questions = get_questions_by_use_case(st.session_state.selected_use_case)

# Show active filter indicator
if st.session_state.selected_use_case != "all":
    use_case_info = USE_CASES[st.session_state.selected_use_case]
    st.info(f"{use_case_info['icon']} Showing questions for **{use_case_info['label']}** use case. Change filter in sidebar.")

# Question selection section - compact layout
col_cat, col_question, col_btn = st.columns([2, 5, 1])

with col_cat:
    # Category dropdown - filtered by use case
    categories = ["-- Select Topic --"] + list(filtered_questions.keys()) + ["Custom Query"]
    selected_category = st.selectbox(
        "Topic:",
        options=categories,
        key="category_select",
        label_visibility="collapsed"
    )

with col_question:
    if selected_category == "-- Select Topic --":
        st.text_input(
            "Question:",
            value="",
            placeholder="← First select a topic, then choose a question",
            disabled=True,
            label_visibility="collapsed",
            key="placeholder_input"
        )
        selected_query = None
    elif selected_category == "Custom Query":
        custom_query = st.text_input(
            "Custom question:",
            placeholder="Type your own question here...",
            label_visibility="collapsed",
            key="custom_query_input"
        )
        selected_query = custom_query if custom_query else None
    else:
        # Show questions dropdown for selected category
        questions = ["-- Select a question --"] + filtered_questions[selected_category]
        selected_q = st.selectbox(
            "Question:",
            options=questions,
            key=f"question_select_{selected_category}",
            label_visibility="collapsed"
        )
        selected_query = selected_q if selected_q != "-- Select a question --" else None

with col_btn:
    ask_disabled = selected_query is None or selected_query == ""
    if st.button("🚀 Ask", disabled=ask_disabled, use_container_width=True, key="ask_btn"):
        if selected_query:
            st.session_state.last_query = selected_query
            st.rerun()

# Display results if we have a last query
if st.session_state.last_query:
    st.divider()

    # Display the submitted query with clear button
    col_query, col_clear = st.columns([5, 1])
    with col_query:
        st.markdown(f"""
        <div class='submitted-query'>
            <div class='submitted-query-label'>Your Question:</div>
            {st.session_state.last_query}
        </div>
        """, unsafe_allow_html=True)
    with col_clear:
        if st.button("🔄 New Query", key="clear_query"):
            st.session_state.last_query = None
            st.session_state.selected_question = ""
            st.rerun()
    
    # Create two columns for side-by-side comparison
    col_left, col_right = st.columns(2)
    
    # Left column - Direct LLM
    with col_left:
        st.markdown("### 💬 Direct LLM Response")
        st.markdown("<small style='color: #666;'>No document context, just the query</small>", unsafe_allow_html=True)
        
        with st.spinner("Querying Ollama..."):
            success, response, metadata = query_direct_llm(st.session_state.last_query)
        
        if success:
            st.markdown(f"""
            <div class='response-container direct-llm'>
                {response}
            </div>
            """, unsafe_allow_html=True)
            
            # Show metadata
            elapsed = metadata.get("elapsed_time", 0)
            model = metadata.get("model", "N/A")
            st.markdown(f"""
            <div class='metadata'>
                <strong>Model:</strong> {model}<br>
                <strong>Response Time:</strong> {elapsed:.2f}s
            </div>
            """, unsafe_allow_html=True)
        else:
            st.error(f"Error: {response}")
    
    # Right column - RAG Enhanced
    with col_right:
        st.markdown("### 🔍 RAG-Enhanced Response")
        st.markdown("<small style='color: #666;'>With retrieved document context</small>", unsafe_allow_html=True)
        
        if st.session_state.indexed_count == 0:
            st.warning("⚠️ No documents indexed. The response will be based on general knowledge.")
        
        with st.spinner("Querying RAG system..."):
            success, response, metadata = query_with_rag(st.session_state.last_query)
        
        if success:
            st.markdown(f"""
            <div class='response-container rag-enhanced'>
                {response}
            </div>
            """, unsafe_allow_html=True)
            
            # Show metadata
            elapsed = metadata.get("elapsed_time", 0)
            sources = metadata.get("sources", [])
            chunks = metadata.get("chunks_used", 0)
            
            sources_text = ", ".join(sources) if sources else "None"
            
            st.markdown(f"""
            <div class='metadata'>
                <strong>Sources:</strong> {sources_text}<br>
                <strong>Chunks Used:</strong> {chunks}<br>
                <strong>Response Time:</strong> {elapsed:.2f}s
            </div>
            """, unsafe_allow_html=True)
        else:
            st.error(f"Error: {response}")

# Footer
st.divider()
st.markdown("""
<div style='text-align: center; color: #666; font-size: 0.85rem; padding: 2rem 0;'>
    <p>Enterprise RAG Platform | Built with Streamlit</p>
    <p>Compare direct LLM responses with RAG-enhanced responses side-by-side</p>
</div>
""", unsafe_allow_html=True)
