# OCI ModelCar — packages the Qwen2.5-7B-Instruct weights as a container image
# so KServe can pull the model from the (mirrored) internal registry in air-gap
# mode via `storageUri: oci://…` instead of `hf://` at runtime (P6, ADR D4).
#
# Built + pushed once by `task mirror` (needs connectivity to Hugging Face at
# BUILD time only); thereafter the cluster pulls the model from the internal /
# disconnected registry — no egress at serve time.
#
# KServe OCI modelcar convention: model files live under /models in the image.
FROM registry.access.redhat.com/ubi9/python-311:1 AS build
ARG MODEL=Qwen/Qwen2.5-7B-Instruct
RUN pip install --no-cache-dir "huggingface_hub[cli]==0.27.*" \
    && huggingface-cli download "${MODEL}" \
        --local-dir /models \
        --exclude "*.pth" "original/*" \
    && find /models -name "*.lock" -delete

# Minimal final layer — just the weights (KServe mounts /models).
FROM registry.access.redhat.com/ubi9/ubi-micro:9.7
COPY --from=build /models /models
# KServe's modelcar sidecar only needs the files present; keep a no-op CMD.
CMD ["/bin/true"]
