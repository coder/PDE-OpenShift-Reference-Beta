# Working implementation guide

This guide lists the steps that took a **fresh AWS account** to the live,
accepted connected-mode environment (2026-11-10). The whole deployment was
driven from **Coder Agents**. Detours and fixes from that run are left out;
their results are already in `main`. Follow the steps in order.

Reference docs: [`deploy.md`](deploy.md) (runbook), [`architecture.md`](architecture.md),
[`air-gap.md`](air-gap.md) (not yet validated live), [`decisions.md`](decisions.md).

What you end up with:
- OpenShift 4.21 on AWS (STS/IRSA) across 2 AZs: 3 control-plane, 3 workers and
  1 `g5.2xlarge` GPU node.
- 11 Argo CD apps, all Synced/Healthy.
- Keycloak SSO into Coder and Gitea.
- Both workspace templates.
- Claude Code, Codex and Coder Agents working through the Coder AI Gateway, to
  in-cluster vLLM (Qwen2.5-7B) and Bedrock (Claude Haiku/Opus 4.5).

---

## Part A: The operator console (Coder Agents + a Coder workspace)

You don't need a laptop toolchain. A **Coder Agents** chat in your company Coder
deployment acts as the operator. It is attached to a **Coder workspace** where
every CLI, the cluster state and the secrets live.

### A1. Create the project and the workspace
1. In Coder Agents, create a **project** for this effort (we used "Red Hat Ref
   Arch Beta"). The project's **memory** is shared by every chat in it. The agent
   saves durable facts there: the account and profile names, the cluster
   identity, DNS zone ids, the Git workflow, traps to avoid, and Coder 2.39
   behaviour. A new chat can then pick up where the last one stopped.
2. Start a chat and have the agent create a workspace from the **Vibe Coding**
   template (Ubuntu, Node/Go/Python, git, jq, Terraform). Ours was called
   `pde-redhat-ref-testing`.
3. Ask the agent to clone the repo into the workspace:
   `git clone https://github.com/coder/PDE-OpenShift-Reference-Beta ~/PDE-OpenShift-Reference-Beta`.
   If you work through a fork, also add it as remote `fork`.

### A2. How the work splits between you and the agent
| Who | Does what | Where |
|---|---|---|
| **Agent** | Reads the repo and docs, installs tools, runs `terraform`, `openshift-install`, `oc`, `task`, `coder`, checks live state, edits docs/manifests, commits and pushes branches | its `execute`/file tools in the workspace |
| **You** | Everything interactive or secret: pasting AWS SSO credentials, uploading the pull secret and license, browser SSO logins, `coder login` token flows, opening/merging PRs | the **Terminal** tab (right sidebar), your browser, GitHub |
| **Both** | Visual checks (Coder UI, Argo, Gitea) | **Desktop** tab, or your own browser |

Ground rules that kept the run clean:
- **Never paste secret values into the chat.** Put them in files under
  `~/pde-deploy/secrets/` from the Terminal tab. The agent validates them
  (with `jq -e`, `test -s`) without printing them.
- Keep all non-repo state in **`~/pde-deploy/`**, outside the git checkout. That
  includes the install dir, ccoctl output, the CLI config and secrets.
- Git workflow: the agent pushes feature branches to the fork, and you open and
  merge the PRs into `coder/PDE-OpenShift-Reference-Beta` `main`. Argo CD
  tracks `main`, so a merge is a deploy.

### A3. Workspace shell setup (do this once)
The agent's commands don't source `~/.bashrc`, so the agent prefixes each
command itself. For **your** Terminal, add to `~/.bashrc`:
```bash
export AWS_PROFILE=<ACCOUNT_ID>_AWSAdministratorAccess
export PATH="$PATH:$HOME/.local/bin"
export KUBECONFIG=$HOME/pde-deploy/cluster/auth/kubeconfig   # never fall back to the workspace's in-cluster SA
```
The agent prefixes its commands with
`export PATH=$HOME/.local/bin:$PATH KUBECONFIG=$HOME/pde-deploy/cluster/auth/kubeconfig`.

> **Two traps specific to running inside a Coder workspace**
> 1. If `KUBECONFIG` is unset, `oc` silently uses the **workspace pod's own
>    service account** on the company cluster. Always set `KUBECONFIG`.
> 2. The workspace's `coder` CLI is pre-authenticated to the **company** Coder
>    through the `CODER_URL`/`CODER_SESSION_TOKEN` env vars. Run every command
>    aimed at the demo Coder (including `task push-templates` / `task ai-provider`) as:
>    ```bash
>    env -u CODER_URL -u CODER_SESSION_TOKEN -u CODER_AGENT_TOKEN -u CODER_AGENT_URL \
>      CODER_CONFIG_DIR=$HOME/pde-deploy/coder-cli <command>
>    ```
>    Below, this prefix is written as **`DEMO_CODER`**. Define it with
>    `alias DEMO_CODER='env -u CODER_URL -u CODER_SESSION_TOKEN -u CODER_AGENT_TOKEN -u CODER_AGENT_URL CODER_CONFIG_DIR=$HOME/pde-deploy/coder-cli'`.

### A4. Install the CLIs (into `~/.local/bin`, so they survive workspace restarts)
Run [`install/install-tools.sh`](../install/install-tools.sh) (you or the agent):
```bash
./install/install-tools.sh          # OCP_VERSION=4.21.42 by default; PREFIX=~/.local; FORCE=1 to reinstall
```
Restarts wipe `/usr/local` and `/opt`, so you'll re-run it after one. It's
idempotent and skips anything already installed. It installs:
- `oc`, `openshift-install`, `ccoctl` and `oc-mirror`, pinned to `OCP_VERSION`,
  from `mirror.openshift.com`. `oc-mirror` is the RHEL9 build. If the OS lacks
  `libgpgme.so.11`/`libassuan.so.0` (Ubuntu does), the script pulls them from
  UBI9 and installs a small `LD_LIBRARY_PATH` wrapper;
- AWS CLI v2 and go-task;
- Terraform and `jq`, only if they aren't already on `PATH`.

It checks for `curl`, `tar`, `unzip` and `python3`, and only supports Linux
x86_64. The `coder` CLI is already in the workspace.

---

## Part B: Fresh-account prerequisites

### B1. AWS credentials
From the AWS access portal, copy the **AdministratorAccess** short-term credentials
for the target account into `~/.aws/credentials` (Terminal tab). Do the same for
the account that owns the **parent** DNS zone (`coderdemo.io`); it's only needed
for the NS delegation and at teardown. The session tokens expire, so refresh them
before any AWS/Terraform step. Check access with:
```bash
aws sts get-caller-identity
```

### B2. Quotas
- **Running On-Demand G and VT instances**: request ≥ 8 vCPU (one
  `g5.2xlarge`). The default is 0.
- **Standard vCPU**: enough for 3× `m6i.xlarge` + 3× `m6i.2xlarge` (+ bootstrap).
- **Elastic IPs**: the default limit is 5, and IPI uses 1 NAT EIP per AZ. We
  chose **2 AZs** (`us-east-1a`/`b`) to stay under it.

### B3. Bedrock models (connected mode)
In Bedrock (us-east-1), make sure the account can invoke **Claude Haiku 4.5** and
**Claude Opus 4.5** through the `global.*` inference profiles. Sonnet 4.5 was
denied as "Legacy" in our account, which is why the repo doesn't use it.

### B4. Secrets (Terminal tab, never committed)
```bash
mkdir -p ~/pde-deploy/secrets && chmod 700 ~/pde-deploy/secrets
# Red Hat pull secret from console.redhat.com -> ~/pde-deploy/secrets/pull-secret.json
# Coder license (Premium + AI governance)      -> ~/pde-deploy/secrets/coder-license.jwt
ssh-keygen -t ed25519 -N '' -f ~/pde-deploy/secrets/id_ed25519   # node SSH key
jq -e '.auths["registry.redhat.io"]' ~/pde-deploy/secrets/pull-secret.json >/dev/null && echo pull-secret OK
```

### B5. Terraform variables
```bash
cd ~/PDE-OpenShift-Reference-Beta/terraform
cp terraform.tfvars.example terraform.tfvars      # gitignored
```
Set `aws_region = "us-east-1"`, `aws_profile = "<ACCOUNT_ID>_AWSAdministratorAccess"`,
`base_domain = "rh-pde.coderdemo.io"`, `cluster_name = "cluster"`,
`create_route53_zone = true`. Leave the `oidc_*` vars commented out for now.

> **Never** change `create_route53_zone` to `false` afterwards. That destroys the
> zone. The Terraform state stays local (`terraform/terraform.tfstate`,
> gitignored), so keep the workspace volume.

### B6. DNS zone and delegation
```bash
terraform init
terraform apply -target=aws_route53_zone.base
terraform output route53_name_servers
```
In the **parent** account, add an `NS` record for `rh-pde.coderdemo.io` in the
`coderdemo.io` zone with those four name servers:
```bash
aws route53 change-resource-record-sets --profile <PARENT_PROFILE> \
  --hosted-zone-id <PARENT_ZONE_ID> --change-batch file://ns-delegation.json   # UPSERT NS, TTL 300
dig +short NS rh-pde.coderdemo.io        # must return the new zone's servers
```

---

## Part C: Install OpenShift (STS / manual credentials)

### C1. install-config
[`install/install-config.yaml.example`](../install/install-config.yaml.example)
matches the live install as committed:
- `baseDomain: rh-pde.coderdemo.io` and `metadata.name: cluster`;
- `credentialsMode: Manual`;
- control plane: 3 × `m6i.xlarge`; compute: 3 × `m6i.2xlarge`;
- `zones: [us-east-1a, us-east-1b]` on both pools.

To change any of these, use a copy and pass it with `--template`. Render it
with the pull secret and public key, which are read from files:
```bash
cd ~/PDE-OpenShift-Reference-Beta
./install/render-install-config.sh \
  --pull-secret ~/pde-deploy/secrets/pull-secret.json \
  --ssh-key     ~/pde-deploy/secrets/id_ed25519.pub \
  --out-dir     ~/pde-deploy/cluster
```
The script validates its inputs and writes
`~/pde-deploy/cluster/install-config.yaml` (mode 0600). It also writes a `.bak`
copy, because `openshift-install` consumes the original. It refuses to write
inside a git checkout.

### C2. STS (ccoctl) and the cluster
```bash
cd ~/pde-deploy
RELEASE_IMAGE=$(openshift-install version | awk '/release image/{print $3}')
oc adm release extract --from="$RELEASE_IMAGE" --credentials-requests --included \
  --install-config=cluster/install-config.yaml --to=credrequests \
  -a secrets/pull-secret.json
ccoctl aws create-all --name rh-pde-cluster --region us-east-1 \
  --credentials-requests-dir credrequests --output-dir ccoctl          # IAM OIDC provider + S3 issuer + operator roles
openshift-install create manifests --dir cluster
cp ccoctl/manifests/* cluster/manifests/ && cp -a ccoctl/tls cluster/
openshift-install create cluster --dir cluster --log-level=info       # ~40 min
```
`openshift-install create cluster` is long-running, so let the agent run it in the
background and poll it. When it finishes, the kubeconfig and kubeadmin password
are in `~/pde-deploy/cluster/auth/`. **Keep `~/pde-deploy/cluster` intact**: you
need it for `openshift-install destroy cluster`.
```bash
oc get nodes && oc get clusterversion
```

### C3. IRSA roles
```bash
oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}'
#  -> https://rh-pde-cluster-oidc.s3.us-east-1.amazonaws.com
```
In `terraform/terraform.tfvars` set:
```hcl
oidc_provider_arn = "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/rh-pde-cluster-oidc.s3.us-east-1.amazonaws.com"
oidc_issuer_host  = "rh-pde-cluster-oidc.s3.us-east-1.amazonaws.com"
enable_bedrock    = true
# create_route53_zone stays true
```
```bash
cd ~/PDE-OpenShift-Reference-Beta/terraform && terraform apply
export CERT_MANAGER_ROLE_ARN=$(terraform output -raw cert_manager_role_arn)
export CODER_BEDROCK_ROLE_ARN=$(terraform output -raw coder_bedrock_role_arn)
```

---

## Part D: Deploy the platform

### D1. `task deploy`
```bash
cd ~/PDE-OpenShift-Reference-Beta
task preflight
task deploy          # connected mode
```
The order is:
1. operators (OLM) → Argo root app-of-apps;
2. annotate the cert-manager SA (IRSA);
3. create the GPU MachineSet (`task gpu-node`, derived from the `us-east-1a`
   worker MachineSet);
4. wait until all 11 apps are Synced/Healthy;
5. annotate the coder SA with the Bedrock role and restart Coder.

On a brand-new deployment, `push-templates` and `ai-provider` **skip
themselves** because nothing is logged into the demo Coder yet. That's
expected; Part E handles it.

The wait is usually 20-30 minutes, mostly the GPU node joining, the NVIDIA
driver build and the Qwen model download. The agent can track it:
```bash
task status
oc get applications.argoproj.io -n openshift-gitops
oc get nodes -l nvidia.com/gpu.present=true
oc get inferenceservice -n rhoai-serving
```

### D2. Check the edge
Open `https://coder.apps.cluster.rh-pde.coderdemo.io`, `https://keycloak.apps…`
and `https://gitea.apps…`. Each should serve a valid Let's Encrypt wildcard cert.
```bash
task creds        # persona + Keycloak admin passwords, read live (run in the Terminal tab)
```

---

## Part E: Bring Coder online

### E1. The first owner (browser)
Password auth is off, so the first OIDC sign-in becomes the **owner**. Open
`https://coder.apps.cluster.rh-pde.coderdemo.io/api/v2/users/oidc/callback` and sign
in to Keycloak as **`demoadm`**. Do this before any other persona logs in.

### E2. CLI login and license (Terminal tab)
```bash
DEMO_CODER coder login https://coder.apps.cluster.rh-pde.coderdemo.io   # browser token flow
#  -> if asked "create the first user?", answer NO
DEMO_CODER coder licenses add -f ~/pde-deploy/secrets/coder-license.jwt
DEMO_CODER coder licenses list        # must be active; telemetry stays enabled (required by the license)
```

### E3. Templates and AI providers
```bash
cd ~/PDE-OpenShift-Reference-Beta
DEMO_CODER task push-templates   # workspace-basic + workspace-agent (image_registry=GHCR, anthropic_model=Haiku 4.5)
DEMO_CODER task ai-provider      # providers openai (vLLM) + bedrock (IRSA); Agents models Opus 4.5 (default), Haiku 4.5, Qwen
```
Both commands are idempotent. Re-run `task push-templates` whenever template
variables change, because a bare `coder templates push` reuses the old variable
values.

### E4. Persona logins (browser)
Coder and Gitea create users **just in time**. Log in once as each persona
(`alice`, `bob`, and `demoadm` again) to:
- Coder, so OIDC group/role sync runs; and
- Gitea (the **keycloak** sign-in option), so the account is created.

After that, add the personas as collaborators on the Gitea repos you use for
the demo.

---

## Part F: Acceptance checks (what "done" looked like)
| Check | How |
|---|---|
| GitOps | `oc get applications.argoproj.io -n openshift-gitops`: 11 apps + root, all Synced/Healthy |
| Model | `oc get inferenceservice -n rhoai-serving`: `qwen25-7b` Ready on the GPU node |
| Identity | each persona can log in to Coder and Gitea; Coder shows the correct groups/roles |
| AI config | Coder → Admin → AI Gateway lists `openai` + `bedrock`; Agents model picker shows Opus 4.5 (default), Haiku 4.5, Qwen |
| Workspaces | create `workspace-basic` and `workspace-agent` from the UI; code-server opens; Gitea clone works through external auth |
| AI round-trip | in `workspace-agent`: **Codex** answers (→ vLLM Qwen) and **Claude Code** answers (→ Bedrock Haiku), with no API-key prompt; a **Coder Agents** chat answers on Opus/Haiku/Qwen |

Have the agent screenshot each UI check through the Desktop tab, or do them in
your own browser.

---

## Part G: Day-2 and teardown
- **Changes:** ask the agent for a branch, have it push to the fork, then
  review and merge the PR yourself. Argo syncs `main` automatically.
- **After a workspace restart:** re-run `./install/install-tools.sh` and
  refresh `~/.aws/credentials`.
- **Reset between demos:** `task reset` re-runs the realm import only (see
  [`deploy.md`](deploy.md#reset-between-demos)). Not yet validated live.
- **Teardown** (in order):
  1. `openshift-install destroy cluster --dir ~/pde-deploy/cluster`
  2. `ccoctl aws delete --name rh-pde-cluster --region us-east-1`
  3. `cd terraform && terraform destroy` (zone + IRSA roles)
  4. delete the `rh-pde.coderdemo.io` NS record from the parent zone (parent account).

## Not covered here
`MODE=airgap`, `task mirror`, `task reset` and observability (D8) haven't been
run live. See [`air-gap.md`](air-gap.md#known-gaps) before trying air-gap.
