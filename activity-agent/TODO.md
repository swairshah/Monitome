# Activity Agent TODO

## Search Performance

Current semantic search sends entire index to LLM on every query - slow and expensive.

### Planned: SQLite FTS5
- Ships with macOS, no dependencies
- Fast full-text search with ranking
- Persists in app's data folder
- Works offline, instant results

### Implementation
1. Create SQLite DB alongside `activity-context.json`
2. FTS5 table indexing: activity, summary, tags, URLs, file paths, etc.
3. Update index on each `processScreenshot()`
4. `search` command uses FTS5 with ranking
5. Optional: LLM re-ranking of top-N results for semantic queries

### Future Enhancements
- **Core ML embeddings**: Use `NLEmbedding` for on-device semantic vectors
- **sqlite-vec**: Add vector column for hybrid keyword + semantic search
- **Core Spotlight**: Index activities in macOS Spotlight for system-wide search

## Other TODOs

- [ ] Session grouping (auto-detect work sessions by time gaps)
- [ ] Activity timeline visualization
- [ ] Export formats (markdown, CSV, JSON)
- [ ] Configurable model selection
- [ ] Batch processing with progress bar
- [ ] Duplicate/similar screenshot detection
