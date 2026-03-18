# Copilot Defaults

- Prefer non-interactive commands over interactive shells unless the task explicitly requires an interactive program.
- Minimize use of interactive terminal flows that can mangle command output in the IDE.
- When running terminal commands, also write the exact command and the resulting output to files under `~/.cache/copilot`.
- Ensure `~/.cache/copilot` exists before attempting to write logs there.
- Use append-safe logging or timestamped files so earlier command logs are not lost unless replacement is explicitly intended.
