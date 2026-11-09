# manifests/model-serving

RHOAI model serving (ADR D3/D4). Synced by the `model-serving` Argo Application
(`gitops/apps/model-serving.yaml`, sync-wave 2) into the `rhoai-serving`
namespace (cluster-scoped RHOAI CRs apply cluster-wide).

| File | Purpose |
|------|---------|
| `dsc-initialization.yaml` | `DSCInitialization` — platform services; **ServiceMesh Removed** (RawDeployment, D3). |
| `datasciencecluster.yaml` | `DataScienceCluster` — **KServe only**, `defaultDeploymentMode: RawDeployment`, Serverless Removed; all other components Removed (D8). |
| `namespace.yaml` | `rhoai-serving` namespace for the serving workloads. |
| `serving-runtime.yaml` | vLLM `ServingRuntime` (Qwen2.5-7B): 16K ctx, TP-1, Hermes tool calling (D4). |
| `inference-service.yaml` | `InferenceService` (RawDeployment) — Qwen2.5-7B on 1× A10G via `hf://` storageUri; GPU request + toleration/nodeSelector. |

The model is OpenAI-compatible; **Coder's AI Gateway** (`gitops/apps/coder.yaml`,
`CODER_AI_GATEWAY_OPENAI_BASE_URL`) routes Agents traffic to the InferenceService
predictor. Bedrock is an optional connected-mode add-on (not wired in P4).

**Infra assumption:** a g5.2xlarge (A10G) GPU MachineSet exists (terraform);
NFD + NVIDIA GPU operator (bootstrap operators) label/taint the GPU node.

**Version note:** RHOAI (ODH) CRD fields and the `quay.io/modh/vllm` image tag
are pinned to a recent RHOAI 2.x; confirm against the installed rhods-operator
at the P7 fresh-cluster acceptance run (no live validation available now).

Scale-up (documented, scaled to 0): Llama-3.3-70B on L40S with tensor parallelism.
