# Token-Preservation Execution Rules

## Primary Policy
Preserve native Claude Pro / Cowork quota by delegating heavy scanning, review, and test generation tasks to Gemini and DeepSeek.

## Routing Rules
1. **Repository Audits & Code Reviews -> `/gemini`**
   - Use `/gemini` for large file reviews, monorepo context scanning, or reading massive log files via Gemini API.
   - Example: `/gemini "Review the changes in src/ controller for security flaws."`

2. **Test Generation & Documentation -> `/deepseek`**
   - Use `/deepseek` for writing unit tests, docstrings, or routine feature boilerplate via DeepSeek-V3.
   - Example: `/deepseek "Write Jest unit tests for services/auth.ts."`

3. **Complex Logic & Debugging -> `/deepseek-r`**
   - Use `/deepseek-r` for heavy algorithmic reasoning or complex bug investigations via DeepSeek-R1.
   - Example: `/deepseek-r "Explain why this database query causes deadlocks."`

4. **File Writes & Orchestration -> Native Claude Code**
   - Use native Claude Code to write edited files to disk, run local git commands, and manage terminal execution.