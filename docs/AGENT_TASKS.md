# Bzzbe Agent Task Catalog (Starter Set)

These are candidate built-in workflows for a local-first assistant.

## 1) Writing & communication

- Draft email from bullet points.
- Rewrite text for tone (formal, friendly, concise).
- Summarize long notes into action items.
- Meeting recap from pasted transcript.

## 2) Study & research

- Explain a concept at beginner/intermediate/advanced depth.
- Build a study plan with checkpoints.
- Flashcard generation from pasted material.
- Compare two concepts in table format.

## 3) Developer workflows

- Explain code snippet and suggest improvements.
- Generate unit tests for selected source.
- Draft commit message and PR summary from diff.
- Refactor suggestion with style constraints.

## 4) Local file tasks

- Batch rename files based on pattern.
- Organize downloads folder by file type/date.
- Summarize a directory of text documents.
- Detect duplicate files by hash (with preview before deletion).

## 5) Productivity automation

- Daily plan creation from goals + calendar text.
- Weekly review summary from notes/journal entries.
- Turn brainstorming notes into project plan.

## 6) Creative tasks

- Story prompt generation.
- Blog outline and first draft.
- Social post variations from a single message.

## Task execution design notes

- Every task should show:
  - objective
  - required inputs
  - estimated duration
  - tools involved
  - confirmation step before irreversible actions

- Safety defaults:
  - dry-run previews for filesystem operations
  - explicit user confirmation for writes/deletes
  - full execution log visible in UI

## Suggested v1 launch subset

Start with high-value, low-risk tasks:
1. text summarization
2. rewrite for tone
3. code explanation
4. test generation
5. folder organization (dry-run first)
