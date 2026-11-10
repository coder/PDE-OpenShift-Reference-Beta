# manifests/model-serving

RHOAI model serving (ADR D3/D4). Synced by the `model-serving` Argo Application
(`gitops/apps/model-serving.yaml`, sync-wave 2) into the `rhoai-serving`
namespace (cluster-scoped RHOAI CRs apply cluster-wide).

| File | Purpose |
|------|---------|
| `dsc-initialization.yaml` | `DSCInitialization` — platform services; **ServiceMesh Removed** (RawDeployment, D3). |
| `datasciencecluster.yaml` | `DataScienceCluster` — **KServe only** (RawDeployment is the only KServe mode in RHOAI 3.x); all other components Removed (D8). |
| `namespace.yaml` | `rhoai-serving` namespace for the serving workloads. |
| `serving-runtime.yaml` | vLLM `ServingRuntime` (Qwen2.5-7B): 16K ctx, TP-1, Hermes tool calling (D4). |
| `inference-service.yaml` | `InferenceService` (RawDeployment) — Qwen2.5-7B on 1× A10G via `hf://` storageUri; GPU request + toleration/nodeSelector. |

The model is OpenAI-compatible (chat completions + Responses API); **Coder's AI
Gateway** routes Agents traffic to the InferenceService predictor through the
`openai` provider that `task ai-provider` registers via the Coder API
(`http://qwen25-7b-predictor.rhoai-serving.svc:8080/v1` — the predictor Service
is headless, so use the pod port). Bedrock (Anthropic, for Claude Code) is an
optional connected-mode provider configured by the same task — see
[`ai-providers/`](../../ai-providers/).

**Infra assumption:** a g5.2xlarge (A10G) GPU MachineSet exists (terraform);
NFD + NVIDIA GPU operator (bootstrap operators) label/taint the GPU node.

**Version note:** the vLLM image is pinned by digest to the one RHOAI 3.5.2
ships (`vllm-cuda-runtime-template`, vLLM v0.24.0); re-pin on RHOAI upgrades
(see the comment in `serving-runtime.yaml`).

Scale-up (documented, scaled to 0): Llama-3.3-70B on L40S with tensor parallelism.
