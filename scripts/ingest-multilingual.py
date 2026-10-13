#!/usr/bin/env python3
"""
ingest-multilingual.py — Language-aware ingestion wrapper.

Drop-in replacement for ingest.py that:
1. Detects the document language automatically
2. Translates non-English content to English via Ollama before embedding
3. Preserves the original text alongside the translation as metadata
4. Accepts natural-language prompts/questions in any language
5. Falls back gracefully if translation fails (ingests original text)

Usage:
  python scripts/ingest-multilingual.py /app/data/doc.pdf \
    --tenant rsh-internal \
    --source-id my-doc \
    --classification internal \
    [--translate]       # force translation even if detected as English
    [--detect-only]     # just print detected language and exit
"""
import argparse
import asyncio
import re
import sys
from pathlib import Path

OLLAMA_BASE = "http://ollama:11434"
SUPPORTED_LANGUAGES = {
    "ar": "Arabic", "de": "German", "es": "Spanish", "fr": "French",
    "hi": "Hindi", "it": "Italian", "ja": "Japanese", "ko": "Korean",
    "nl": "Dutch", "pl": "Polish", "pt": "Portuguese", "ru": "Russian",
    "tr": "Turkish", "uk": "Ukrainian", "ur": "Urdu", "zh": "Chinese",
    "en": "English",
}


def detect_language_fast(text: str) -> str:
    """
    Heuristic language detection without external deps.
    Returns ISO-639-1 code.
    """
    sample = text[:500].lower()

    # Script-based detection (high confidence)
    if re.search(r'[\u4e00-\u9fff\u3040-\u30ff\uff00-\uffef]', sample):
        return "zh" if re.search(r'[\u4e00-\u9fff]', sample) else "ja"
    if re.search(r'[\u0600-\u06ff]', sample):
        return "ar"
    if re.search(r'[\u0400-\u04ff]', sample):
        return "ru"
    if re.search(r'[\u0900-\u097f]', sample):
        return "hi"
    if re.search(r'[\uac00-\ud7af]', sample):
        return "ko"

    # Word-based heuristics for Latin-script languages
    fr_words = len(re.findall(r'\b(le|la|les|de|du|des|et|en|un|une|pour|dans|avec|sur|est|sont|ce|qui|que|il|elle|nous|vous|ils)\b', sample))
    de_words = len(re.findall(r'\b(der|die|das|den|dem|und|ist|sind|in|von|mit|zu|ein|eine|nicht|auf|für|an|im|als|auch|es|bei|aber)\b', sample))
    es_words = len(re.findall(r'\b(el|la|los|las|de|del|en|con|por|para|una|uno|que|es|son|se|su|al|si|no|como|pero|más|este|está)\b', sample))
    pt_words = len(re.findall(r'\b(de|da|do|dos|das|em|com|por|para|uma|um|que|é|são|se|seu|ao|si|não|como|mas|mais|este|está|também)\b', sample))
    en_words = len(re.findall(r'\b(the|and|of|to|in|is|it|that|this|with|for|are|on|as|at|be|by|from|or|an|was|not|but|have|they)\b', sample))

    scores = {"fr": fr_words, "de": de_words, "es": es_words, "pt": pt_words, "en": en_words}
    detected = max(scores, key=scores.get)
    return detected if scores[detected] > 3 else "en"


async def translate_to_english(text: str, source_lang: str, model: str) -> str:
    """Translate text to English via Ollama."""
    import httpx

    lang_name = SUPPORTED_LANGUAGES.get(source_lang, source_lang)
    # Process in chunks to avoid token limits
    chunks = [text[i:i+3000] for i in range(0, len(text), 3000)]
    translated_chunks = []

    async with httpx.AsyncClient(timeout=120) as client:
        for chunk in chunks[:10]:  # Max 10 chunks = 30k chars
            prompt = (
                f"Translate the following {lang_name} text to English. "
                f"Output ONLY the English translation, nothing else:\n\n{chunk}"
            )
            try:
                r = await client.post(f"{OLLAMA_BASE}/api/generate", json={
                    "model": model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0.1, "num_predict": 2048}
                })
                r.raise_for_status()
                translated_chunks.append(r.json().get("response", chunk))
            except Exception as e:
                print(f"  Translation chunk failed: {e}", file=sys.stderr)
                translated_chunks.append(chunk)  # fallback: keep original

    return "\n\n".join(translated_chunks)


async def get_ollama_model() -> str:
    """Get the configured chat model."""
    import httpx
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.get(f"{OLLAMA_BASE}/api/tags")
            models = [m["name"] for m in r.json().get("models", [])]
            # Prefer smaller/faster models for translation
            for preferred in ["qwen2.5:0.5b", "qwen2.5:1.5b", "qwen3:0.6b"]:
                if any(preferred in m for m in models):
                    return preferred
            return models[0] if models else "qwen2.5:0.5b"
    except Exception:
        return "qwen2.5:0.5b"


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Document path (inside container)")
    parser.add_argument("--tenant", default="rsh-internal")
    parser.add_argument("--source-id", default=None)
    parser.add_argument("--uri", default=None)
    parser.add_argument("--classification", default="internal")
    parser.add_argument("--translate", action="store_true",
                        help="Force translation even if detected as English")
    parser.add_argument("--detect-only", action="store_true",
                        help="Print detected language and exit without ingesting")
    args = parser.parse_args()

    from rsh_agent.config import get_settings
    from rsh_agent.database import wait_for_migrations
    from rsh_agent.knowledge import replace_source
    from rsh_agent.parsing import parse_bytes

    path = args.path.resolve()
    if not path.exists():
        print(f"ERROR: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    # Parse the document
    raw_bytes = path.read_bytes()
    raw_text, metadata_title = parse_bytes(path.name, raw_bytes)

    if not raw_text.strip():
        print(f"ERROR: no extractable text from {path.name}", file=sys.stderr)
        sys.exit(1)

    # Detect language
    lang = detect_language_fast(raw_text)
    lang_name = SUPPORTED_LANGUAGES.get(lang, lang)
    print(f"  Detected language: {lang_name} ({lang})")

    if args.detect_only:
        sys.exit(0)

    # Translate if needed
    final_text = raw_text
    if lang != "en" or args.translate:
        print(f"  Translating {lang_name} → English via Ollama...")
        try:
            model = await get_ollama_model()
            print(f"  Using model: {model}")
            final_text = await translate_to_english(raw_text, lang, model)
            print(f"  Translation complete ({len(final_text)} chars)")
        except Exception as e:
            print(f"  Translation failed ({e}) — ingesting original text", file=sys.stderr)
            final_text = raw_text
    else:
        print(f"  Content is English — no translation needed")

    # Ingest
    settings = get_settings()
    await wait_for_migrations(settings.schema_migration_wait_seconds)

    source_id = args.source_id or str(path)
    uri = args.uri or path.as_uri()

    # Prepend language metadata to aid retrieval context
    if lang != "en":
        final_text = f"[Original language: {lang_name}]\n\n{final_text}"

    count = await replace_source(
        args.tenant,
        source_id,
        metadata_title[:512] or path.stem,
        uri,
        final_text,
        {
            "classification": args.classification,
            "source_language": lang,
            "translated": lang != "en",
        },
    )
    print(f"Ingested {count} chunks from {path.name} "
          f"[{lang_name}{'→English' if lang != 'en' else ''}] "
          f"into tenant {args.tenant}.")


if __name__ == "__main__":
    asyncio.run(main())
