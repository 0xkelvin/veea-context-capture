# AGENTS.md

## Purpose
This document defines the rules, structure, and safety guidelines for agent code in this project. The app is designed as a "second brain" for mobile devices, focusing on personal knowledge management, privacy, and user safety.

---

## Agent Code Structure
- **Modular Design:** Each agent is a self-contained module with a clear responsibility.
- **Naming Conventions:**
  - Use descriptive, lowercase names with underscores for files and classes (e.g., `note_agent.py`, `capture_agent.py`).
  - Agent classes should end with `Agent` (e.g., `TaskAgent`).
- **Documentation:**
  - Every agent must have a docstring explaining its purpose and usage.
  - Public methods should include parameter and return value descriptions.
- **Testing:**
  - Each agent must have corresponding unit tests.
  - Tests should cover normal, edge, and failure cases.

---

## Rules for Agents
- **Single Responsibility:** Each agent should focus on a single domain (e.g., note capture, search, summarization).
- **Extensibility:** Agents should be easy to extend or replace without affecting others.
- **Error Handling:**
  - Handle all exceptions gracefully.
  - Never crash the app; always provide user feedback on errors.
- **Data Privacy:**
  - Never share user data without explicit permission.
  - Store sensitive data securely using platform best practices.
- **Resource Management:**
  - Release resources (memory, files, network) when not needed.

---

## Safety Rules
- **User Consent:**
  - Always ask for user consent before accessing sensitive data (contacts, location, microphone, etc.).
- **Data Encryption:**
  - Encrypt all personal data at rest and in transit.
- **No External Sharing:**
  - Do not send data to external servers unless required and approved by the user.
- **Transparency:**
  - Clearly inform users about what data is collected and how it is used.
- **Auditability:**
  - Log agent actions for user review, but never log sensitive content.

---

## Backend Folder Structure (Python)

Recommended structure for backend agents and services:

```
backend/
  agents/
    note_agent.py
    capture_agent.py
    ...
  services/
    storage_service.py
    encryption_service.py
    ...
  tests/
    test_note_agent.py
    test_capture_agent.py
    ...
  main.py
  requirements.txt
  README.md
```

- Place each agent in its own file under `agents/`.
- Place shared logic (e.g., storage, encryption) in `services/`.
- All tests go in `tests/` and should cover both normal and edge cases.
- Use `requirements.txt` to manage dependencies.

---

## Example Agent Skeleton (Python)

```python
"""NoteAgent handles note capture and retrieval."""
class NoteAgent:
    def __init__(self):
        pass
    # ...agent implementation...
```

---

## Review & Updates
- Review this document regularly as the app evolves.
- All changes must be approved by the project owner.
