# Shell pitfalls evaluation

From the repository root, list the task and validate its grader without calling a model:

```sh
task eval:skills:list
task eval:skills:validate
```

Validation runs the known-good reference script and checks its result. It tests the grader; it does not measure an agent. To run an actual model evaluation explicitly, use:

```sh
task eval:skills
task eval:skills -- --trials=3 --agent=codex
```

Arguments after `--` become Skillgrade options through Task's `CLI_ARGS`. For example, `--trials`, `--agent`, `--model`, `--provider`, and `--eval` override the corresponding choices for that run. The default is one trial with the Codex CLI, its configured model and authentication, and Skillgrade's local provider. Install and authenticate Codex before running a model trial; model use may incur charges. The managed `skillgrade` launcher uses the pinned package without a global installation.

The task asks an agent to repair a zsh script that copies top-level text files. The grader runs the script with `zsh -f`. The deterministic grader checks files with spaces and shell metacharacters, empty input, and preservation of unrelated files. The shell-pitfalls skill is copied into the agent's discovery paths. Results are stored under `~/.cache/codex/skillgrade`.

The local provider copies the evaluation into a temporary workspace and starts Codex with sandboxed automatic execution. It runs on the host and inherits the host environment and Codex settings; it is not a container. Skillgrade 0.5.0 also uses the fixed path `/tmp/.prompt.md` for its prompt, so concurrent runs can interfere and that prompt file can remain after a run.
