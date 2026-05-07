---
name: amazon-bedrock
description: Build generative AI applications on Amazon Bedrock. Covers model invocation (Converse API, InvokeModel), RAG with Knowledge Bases, Bedrock Agents, Guardrails, and AgentCore. Use when invoking models, setting up Knowledge Bases, creating agents, applying guardrails, troubleshooting errors (ThrottlingException, AccessDeniedException, UnknownOperationException), or selecting models (Claude, Llama, Nova, Titan). Also covers prompt caching, quota health, cost tracking, and migrating between Claude generations.
origin: aws/agent-toolkit-for-aws
---

# Amazon Bedrock

## API Landscape

Bedrock has **5 separate endpoint families** — using the wrong one causes UnknownOperationException:

| Endpoint | Client | Use For |
|---|---|---|
| `bedrock` | Control plane | List models, manage access, provisioned throughput |
| `bedrock-runtime` | Data plane | Converse API, InvokeModel, ConverseStream |
| `bedrock-mantle` | Data plane | OpenAI-compatible APIs (Responses API, Chat Completions, Messages API) — recommended for new users |
| `bedrock-agent` | Agent control | Create/configure agents, Knowledge Bases, action groups |
| `bedrock-agent-runtime` | Agent data | Invoke agents, query Knowledge Bases |

AgentCore adds its own endpoints: `bedrock-agentcore-control` (control plane) and `bedrock-agentcore` (data plane).

## Critical Warnings

**Always set `maxTokens` explicitly.** Leaving it unset defaults to the model's maximum (e.g., 64K for Claude Sonnet) and silently reserves far more quota than needed — a leading cause of unexpected ThrottlingException.

**Guardrails PII logging gap.** PII masking applies only to the API response. Unmasked content including PII is still logged to CloudWatch in plain text. For HIPAA/GDPR: encrypt CloudWatch Logs with KMS, restrict access with IAM, use Amazon Macie for PII detection.

**SDK versions.** Requires boto3 ≥ 1.34.x and AWS CLI v2. Older versions lack Converse API, Agents, and AgentCore support. Check: `aws --version && pip show boto3`.

## Converse API vs InvokeModel

Prefer **Converse API** — unified request/response format across all models:

```bash
aws bedrock-runtime converse \
  --model-id us.anthropic.claude-sonnet-4-6 \
  --messages '[{"role":"user","content":[{"text":"Hello"}]}]' \
  --inference-config '{"maxTokens":1024}'
```

Use **InvokeModel** only for provider-specific features not in Converse. Each provider has a different body format — wrong format produces "Malformed input request".

**Streaming**: The AWS CLI does not support `ConverseStream`. Use the SDK (`converse_stream()` in boto3, `ConverseStreamCommand` in JS SDK) for interactive/chat applications.

## Capability Decision Table

| Goal | API / Service |
|---|---|
| Call a model (text, image, video) | Converse API via `bedrock-runtime` |
| Build a RAG application | Knowledge Bases (`bedrock-agent` + `bedrock-agent-runtime`) |
| Create an agent that takes actions | Bedrock Agents with action groups |
| Filter harmful/sensitive content | Guardrails |
| Deploy and scale an agent | AgentCore Runtime |
| Expose REST APIs as MCP tools | AgentCore Gateway |
| OpenAI-compatible SDK migration | `bedrock-mantle` endpoint |

## Common Workflows

### Verify setup

```bash
aws --version                                          # need v2
aws bedrock list-foundation-models --region us-east-1  # check model access
```

### Invoke a model

```bash
# Cross-region prefix (us./eu./apac./global.) improves availability
aws bedrock-runtime converse \
  --model-id us.anthropic.claude-sonnet-4-6 \
  --messages '[{"role":"user","content":[{"text":"What is Bedrock?"}]}]' \
  --inference-config '{"maxTokens":1024}'
```

### Query a Knowledge Base

| Mode | When to use | Command |
|---|---|---|
| Retrieve & Generate | Quick answer with citations | `aws bedrock-agent-runtime retrieve-and-generate --input '{"text":"<query>"}' --retrieve-and-generate-configuration '{"type":"KNOWLEDGE_BASE","knowledgeBaseConfiguration":{"knowledgeBaseId":"<kb-id>","modelArn":"<model-arn>"}}'` |
| Retrieve only | Raw chunks for custom post-processing | `aws bedrock-agent-runtime retrieve --knowledge-base-id <kb-id> --retrieval-query '{"text":"<query>"}'` |
| Full control | Custom prompt, reranking, multi-KB | Retrieve chunks → build prompt → call `bedrock-runtime converse` |

### Check quota health

```bash
# Get current ThrottlingExceptions metric
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name ThrottlingException \
  --start-time 2024-01-01T00:00:00Z --end-time 2024-01-02T00:00:00Z \
  --period 3600 --statistics Sum

# Check service quota for a model
aws service-quotas get-service-quota \
  --service-code bedrock \
  --quota-code <quota-code>
```

### Error retry strategy

```python
from botocore.config import Config
client = boto3.client(
    "bedrock-runtime",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"})
)
```

## Model Defaults

Verify current availability with `aws bedrock list-foundation-models --region <region>`:

| Use case | Model |
|---|---|
| General purpose | `us.anthropic.claude-sonnet-4-6` |
| Fast + cheap | `us.anthropic.claude-haiku-4-5-20251001` or `amazon.nova-micro-v1:0` |
| Embeddings for Knowledge Base | `amazon.titan-embed-text-v2:0` |
| Open-source / fine-tuning | Llama 3.x |
| Image generation | `amazon.titan-image-generator-v2:0` |

Cross-region prefix (`us.`, `eu.`, `apac.`, `global.`) routes through Bedrock's inference profile network for higher availability. Use `aws bedrock list-inference-profiles --region <region>` to discover available profiles.

## Troubleshooting

| Error | Likely Cause | Fix |
|---|---|---|
| `ThrottlingException` | `maxTokens` not set (reserves max quota) | Set `maxTokens` explicitly; use adaptive retry; use cross-region inference profile |
| `AccessDeniedException` | Missing IAM permissions, model access not enabled, SCP block, or IAM propagation delay | Enable model in Bedrock console; check IAM policies; wait ~30s for role propagation |
| `Malformed input request` | Wrong InvokeModel body format for provider | Use Converse API instead; check provider-specific body schema |
| `UnknownOperationException` | Wrong client endpoint | Check API landscape table — `bedrock` ≠ `bedrock-runtime` |
| Agent returns stale behavior | Skipped `prepare-agent` after config change | Always run `prepare-agent` after any configuration change |
| KB returns empty results | Ingestion not complete | Run `start-ingestion-job` and wait for completion |
| KB retrieval quality poor | Suboptimal chunking | Use advanced parsing (FM-based) for PDFs with tables; configure metadata filtering |
| Zero `cacheReadInputTokens` | Prompt cache not working | Verify model supports caching; check minimum token threshold; ensure content is identical between calls |
| `400` on prefill with Claude 4.6+ | Prefill removed in Claude 4.6 | Remove `prefill` from request body |
| On-demand throughput not supported | Base model ID used where inference profile required | Use `aws bedrock list-inference-profiles` to get profile ID; update agent's `foundationModel` |
| `INVALID_PAYMENT_INSTRUMENT` | Account billing issue | Set credit card as default payment or add USD payment profile |

| Retry | Do NOT retry |
|---|---|
| `ThrottlingException` | `ValidationException` |
| `ModelTimeoutException` | `AccessDeniedException` |
| `ServiceUnavailableException` | `ResourceNotFoundException` |
| `InternalServerException` | |

## Security

- Use IAM **roles** (not IAM users) for all Bedrock access
- Scope permissions to specific actions and resource ARNs — avoid `bedrock:*` or `AmazonBedrockFullAccess`
- Store secrets in **AWS Secrets Manager** with automatic rotation
- Add confused deputy protection (`aws:SourceAccount`, `aws:SourceArn`) in resource-based policies
- Treat all **agent-generated parameters as untrusted input** — validate in Lambda handlers
- Enable **CloudTrail** for all Bedrock and AgentCore API calls

## AgentCore Services

| Service | Use For |
|---|---|
| Gateway | Expose APIs, Lambda functions, or MCP servers as agent tools |
| Runtime | Deploy and scale agents (serverless, any framework) |
| Memory | Short-term (multi-turn) and long-term (cross-session) memory; share memory across agents |
| Identity | Agent auth with external IdPs (Okta, Entra ID, Cognito); act on behalf of users |
| Policy | Enforce agent boundaries with natural language or Cedar rules |
| Registry | Catalog and discover agents, MCP servers, tools, and skills |
| Evaluations | Automated agent quality assessment (LLM-as-a-Judge) |

For AgentCore CLI-based deployment (the `agentcore` npm CLI), see the [aws-agentcore skill](../aws-agentcore/SKILL.md).
