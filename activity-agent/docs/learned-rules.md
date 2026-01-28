# Learned Rules System

The activity agent can learn and adapt based on user feedback. Rules are stored as simple text and injected into the LLM prompt, allowing the agent to improve over time without code changes.

## Overview

```
User Feedback (natural language)
        ↓
   LLM interprets
        ↓
   Updates rules
        ↓
  Saved to disk
        ↓
 Injected into prompts
```

## Rule Categories

### 1. Indexing Rules
Tell the agent **what to extract** from screenshots.

```bash
# Examples
./activity-agent feedback "for Obsidian, extract vault name and [[wiki links]]"
./activity-agent feedback "when viewing GitHub PRs, always extract the PR number and author"
./activity-agent feedback "for Figma, extract project name and frame names"
```

These rules are appended to the indexing prompt:
```
ADDITIONAL INDEXING RULES (learned from user feedback):
1. For Obsidian: extract vault name from window title and identify [[wiki links]] in visible content
2. For GitHub PRs: extract PR number, author, and repository name
```

### 2. Exclude Rules
Tell the agent **what NOT to index**.

```bash
# Examples
./activity-agent feedback "don't index terminal command output"
./activity-agent feedback "skip system notifications and alerts"
./activity-agent feedback "ignore the Monitome recording overlay"
```

These rules are appended as exclusions:
```
DO NOT INDEX / EXCLUDE:
1. Don't index terminal command output, only index the actual commands
2. Skip system notifications and alert dialogs
```

### 3. Search Rules
Tell the agent about **synonyms and search matching**.

```bash
# Examples
./activity-agent feedback "when searching for 'CLI' also match 'terminal' and 'command line'"
./activity-agent feedback "'blog' should match 'article' and 'post'"
./activity-agent feedback "'docker' should also find 'containers' and 'kubernetes'"
```

These rules are used during semantic search:
```
SEARCH RULES (learned from user feedback):
1. 'CLI' should match 'terminal', 'command line', 'shell'
2. 'blog' should match 'article', 'post', 'write-up'
```

## Commands

### Add/Modify Rules
```bash
./activity-agent feedback "<natural language feedback>"
```

The LLM interprets your feedback and decides:
- Which category (indexing/exclude/search)
- Whether to add, modify, or remove a rule
- The exact rule text

### View Rules
```bash
./activity-agent rules
```

Output:
```
Current Learned Rules:

INDEXING RULES (what to extract):
  1. For Obsidian: extract vault name and [[wiki links]]

EXCLUDE RULES (what to skip):
  1. Don't index terminal command output

SEARCH RULES (synonyms/matching):
  1. 'CLI' should match 'terminal', 'command line', 'shell'
```

### Remove Rules
```bash
./activity-agent feedback "remove the rule about CLI synonyms"
./activity-agent feedback "delete the Obsidian indexing rule"
```

### View History
```bash
./activity-agent history
```

Output:
```
Rules Change History:

[1/27/2026, 9:34:21 PM] ADD indexing
  Rule: "For Obsidian: extract vault name and [[wiki links]]"
  Feedback: "for Obsidian, extract vault name and wiki links"

[1/27/2026, 9:35:00 PM] ADD search
  Rule: "'CLI' should match 'terminal', 'command line', 'shell'"
  Feedback: "when searching for CLI also match terminal"
```

### Undo Changes
```bash
./activity-agent undo
```

Reverts the last rule change. Can be called multiple times to undo multiple changes.

## File Storage

Rules are stored in the data directory:

```
data/
├── activity-context.json   # Screenshot index
├── learned-rules.json      # Current active rules
└── rules-history.json      # Full change history
```

### learned-rules.json
```json
{
  "indexing": [
    "For Obsidian: extract vault name and [[wiki links]]"
  ],
  "exclude": [
    "Don't index terminal command output"
  ],
  "search": [
    "'CLI' should match 'terminal', 'command line', 'shell'"
  ],
  "lastUpdated": 1706400000000
}
```

### rules-history.json
```json
{
  "changes": [
    {
      "id": "1706400000000-abc123",
      "timestamp": 1706400000000,
      "feedback": "for Obsidian, extract vault name and wiki links",
      "action": "add",
      "category": "indexing",
      "rule": "For Obsidian: extract vault name and [[wiki links]]"
    }
  ]
}
```

## Integration with Swift App

The Swift app can interact with rules in two ways:

### 1. CLI Commands
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/path/to/activity-agent")
process.arguments = ["feedback", userFeedback]
try process.run()
```

### 2. Direct File Access
Write feedback to a queue file, then call the agent:

```swift
// Write user feedback
let feedback = ["pending": [userFeedback]]
let data = try JSONEncoder().encode(feedback)
try data.write(to: feedbackQueueURL)

// Process feedback
let process = Process()
process.arguments = ["process-feedback"]
try process.run()
```

### 3. Read Current Rules
```swift
let rulesURL = dataDir.appendingPathComponent("learned-rules.json")
let data = try Data(contentsOf: rulesURL)
let rules = try JSONDecoder().decode(LearnedRules.self, from: data)
```

## Example Workflow

1. User searches for "java blog" but doesn't find the expected article
2. User provides feedback: "the search for 'java blog' should have found the xam.dk article about Java CLI"
3. Agent interprets this and adds a search rule: "'blog' should match 'article'"
4. Future searches for "blog" will also match entries tagged with "article"

Or for indexing:

1. User notices Obsidian screenshots don't capture note links
2. User provides feedback: "for Obsidian, always extract [[wiki links]] from the content"
3. Agent adds indexing rule
4. Future Obsidian screenshots will have wiki links extracted and tagged

## How Rules Affect Prompts

### Indexing Prompt (before)
```
You are indexing screenshots for a personal activity search engine...
```

### Indexing Prompt (after rules)
```
You are indexing screenshots for a personal activity search engine...

ADDITIONAL INDEXING RULES (learned from user feedback):
1. For Obsidian: extract vault name and [[wiki links]]

DO NOT INDEX / EXCLUDE:
1. Don't index terminal command output
```

The LLM sees these rules as part of its instructions and follows them when processing new screenshots.
