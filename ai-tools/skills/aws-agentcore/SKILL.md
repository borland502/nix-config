---
name: aws-agentcore
description: Build and deploy AI agents on AWS using the AgentCore CLI. Covers project creation, framework selection (Strands, LangGraph), local dev, deployment, memory, multi-agent, and tool connections. Use when creating a new AgentCore project, deploying agents to AWS, or adding capabilities (memory, gateway, VPC) to an existing project. Requires the agentcore CLI (npm install -g @aws/agentcore) and Node.js 20+.
origin: aws/agent-toolkit-for-aws
---

# AWS AgentCore

The AgentCore CLI scaffolds, runs, and deploys AI agents on AWS (Amazon Bedrock Runtime).

## Prerequisites

```bash
npm install -g @aws/agentcore    # requires Node.js 20+
agentcore --version              # must be ≥0.9.0
agentcore update                 # update if outdated
```

## AgentCore vs Direct Bedrock

| Need | Use This Skill | Use amazon-bedrock Skill |
|---|---|---|
| Scaffold and deploy an agent project | Yes — `agentcore create` + `agentcore deploy` | No |
| Call a model directly (no agent scaffolding) | No | Yes — Converse API |
| Set up RAG / Knowledge Bases | No | Yes — Bedrock Agents |
| Choose which model the agent uses | Both — model set in `app/<Name>/model/load.py`; model IDs from amazon-bedrock skill | |
| Debug ThrottlingException or quota issues | No | Yes |

AgentCore is a deployment and lifecycle layer on top of Amazon Bedrock Runtime — not a replacement for direct model invocation.

## Framework Selection

| Framework | CLI value | Best for |
|---|---|---|
| Strands | `Strands` | AWS-native, simplest path, best AgentCore integration (default) |
| LangGraph | `LangChain_LangGraph` | Complex graph-based workflows, existing LangChain investment |
| Google ADK | `GoogleADK` | Teams using Google's agent toolkit |
| OpenAI Agents | `OpenAIAgents` | Teams using OpenAI's agent SDK |
| BYO Container | (see below) | Any language/framework via HTTP contract |

Framework = how the agent orchestrates. Model provider (Bedrock, Anthropic, OpenAI) is a separate choice.

## Create a Project

```bash
# Minimal (all defaults — Strands, Bedrock, CodeZip, no memory)
agentcore create --name MyAgent --defaults

# With specific options
agentcore create \
  --name MyAgent \
  --framework Strands \
  --model-provider Bedrock \
  --build CodeZip \
  --memory none
```

**Name constraints** — validate before running: max 23 chars, alphanumeric only, starts with a letter. No hyphens, underscores, or spaces.

| Flag | Values | Default |
|---|---|---|
| `--name` | alphanumeric, max 23 chars | prompted |
| `--framework` | `Strands`, `LangChain_LangGraph`, `GoogleADK`, `OpenAIAgents` | prompted |
| `--build` | `CodeZip`, `Container` | `CodeZip` |
| `--model-provider` | `Bedrock`, `Anthropic`, `OpenAI`, `Gemini` | prompted |
| `--memory` | `none`, `shortTerm`, `longAndShortTerm` | prompted |
| `--network-mode` | `PUBLIC`, `VPC` | `PUBLIC` |
| `--dry-run` | — | preview without creating |

## Project Structure

```
<ProjectName>/
├── agentcore/
│   ├── agentcore.json      ← Project config (agents, resources)
│   ├── aws-targets.json    ← AWS account + region
│   ├── .env.local          ← Local env vars (gitignored)
│   └── cdk/                ← CDK infra (auto-managed — don't edit)
└── app/
    └── <AgentName>/
        ├── main.py          ← Agent code — add tools/prompts here
        └── pyproject.toml   ← Python dependencies
```

**Edit `app/<AgentName>/main.py`** for agent logic. `agentcore.json` is managed by CLI commands.

## Local Development

```bash
agentcore dev
```

Starts a local dev server. Default ports: HTTP=8080, MCP=8000, A2A=9000. CLI prints actual bound port — use `--port N` to pin it if the default is taken.

**Local dev limitations**: Memory and gateway URLs require a deploy — they're not available locally.

## Changing the Model

Edit `app/<AgentName>/model/load.py`:

```python
return BedrockModel(model_id="global.anthropic.claude-sonnet-4-5-20250929-v1:0")  # default
return BedrockModel(model_id="us.anthropic.claude-3-5-haiku-20241022-v1:0")       # cost savings
return BedrockModel(model_id="amazon.nova-lite-v1:0")                             # Nova
```

Cross-region prefix: `us.`, `eu.`, `apac.`, `global.` (for throughput). Enable the model in Bedrock → Model access before use.

## Deploy

```bash
agentcore deploy     # first deploy: 3-5 min; subsequent deploys faster
agentcore status     # check deployment status
agentcore invoke "Hello, what can you do?"  # test deployed agent
```

## Add Capabilities

```bash
agentcore add memory          # cross-session memory
agentcore add gateway         # connect to external APIs/tools
agentcore add policy-engine   # guardrails and content policies
agentcore add evaluator       # quality evaluation
agentcore fetch access        # get SDK credentials to call agent from app
```

**For most additions, use `--name`**: max 48 chars, alphanumeric + `_`, starts with a letter.

## Multi-Agent (A2A)

```bash
agentcore create --name Orchestrator --protocol A2A
agentcore create --name Specialist   --protocol A2A
```

A2A enables agent-to-agent delegation. Orchestrator routes tasks to specialists.

## VPC Networking

```bash
agentcore create --name MyAgent --network-mode VPC
```

Required when the agent needs to reach private resources (RDS, internal APIs). Specify subnet IDs and security groups in `agentcore.json`.

## BYO Container (Any Framework/Language)

```bash
agentcore create --name MyAgent --defaults
agentcore add agent --type byo --build Container --language Other --code-location ./src
```

Implement the HTTP contract in your container: `POST /invocations`, `GET /ping`. AgentCore handles ECR push and CDK infra.

Java: Use the Spring AI SDK for AgentCore — it handles SSE streaming and health checks automatically.

## Next Steps After First Deploy

| Goal | Command |
|---|---|
| Call from an app | `agentcore fetch access` |
| Add memory | `agentcore add memory` |
| Connect external APIs | `agentcore add gateway` |
| Production hardening | `agentcore add policy-engine` + IAM review |
| Multi-agent | `agentcore create --protocol A2A` |
