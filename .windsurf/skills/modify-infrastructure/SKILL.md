---
name: modify-infrastructure
description: "Deployment and infrastructure patterns for the CheddarFlow project. TRIGGER when: working with deployment, infrastructure, OpenTofu/Terraform, Ansible, CI/CD workflows, release configuration, AWS resources, or deploy_ex. Also trigger when modifying GitHub Actions workflows, Dockerfiles, or cloud-init templates. DO NOT TRIGGER when: working with application-level Elixir code that doesn't touch infrastructure."
---

# Deployment & Infrastructure

## AWS Rules

- **Always use `AWS_PROFILE=cheddarflow`** for any AWS, tofu, or ansible command
- **Always use `tofu`** instead of `terraform`
- **Always use `--var-file prod.tfvars`** (or `staging.tfvars`)
- **Always prefer mix terraform over tofu**

## Release Architecture

11 Mix releases via `deploy_ex`, each on separate AWS EC2 instances:

```
cfx_web, cfx_bg_processor, options_chain_processor, options_events_processor,
dark_pool_events_processor, options_feed, dark_pool_lit_feed, gamma_exposure_feed,
discord_service, cfx_cms, cfx_hooks_web
```

Releases defined in root `mix.exs` under `releases/0`:
- `applications:` — Primary app(s) as `:permanent`
- `tools()` — Common runtime tools (`runtime_tools`, `observer_cli`, `etop`)
- `cookie:` — From `ERLANG_COOKIE` env var
- `steps: [:assemble, :tar]` — Build as tarball
- Optional `config_providers:` for `cfx_bg_processor` and `options_chain_processor`

`dark_pool_lit_feed` co-hosts `options_unusual_volume_feed`.

## Infrastructure (OpenTofu)

Managed in `deploys/terraform/`:
- Workspaces: `staging` and `prod`
- All instances in `us-east-1`

Key resources: EC2 instances, RDS PostgreSQL, ElastiCache Redis, S3 for release artifacts, VPC, IAM.

## Ansible

`deploys/ansible/` — Playbooks for provisioning EC2, service config, deployment. Used by `deploy_ex`.

## CI/CD (GitHub Actions)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR / push to main,develop | Compile and checks |
| `quality.yml` | PR | Credo linting |
| `coverage.yml` | PR | ExCoveralls coverage |
| `dialyzer.yml` | PR | Static analysis |
| `security.yml` | PR | Sobelow scanning |
| `cd.yml` | Push to main/develop | Triggers deploy |
| `deploy.yml` | Called by cd.yml | Build, upload S3, deploy |

## Deploy Workflow

1. Checkout in `mikaak/elixir-terraform-ansible-builder` container
2. Load secrets from **1Password** via `op` CLI
3. Build releases with `mix deploy_ex.release --force`
4. Init OpenTofu, refresh state
5. Authorize runner SSH key
6. Upload tarballs to S3
7. Rolling deploy via Ansible
8. Deauthorize SSH key

## Local Development

- `brew bundle` (from `Brewfile`)
- `.tool-versions` for Erlang/Elixir/Node (use `asdf install`)
- Docker Compose: `docker/docker-compose.dev.yml`
- `config/dev.secret.exs` for local secrets (not committed)
- `mix docker.up` / `mix docker.down`

## Accessing Production

```bash
cd deploys/terraform
tofu init
tofu workspace select prod
cd ../..
mix deploy_ex.ssh.authorize
ssh admin@<ip> -i deploys/terraform/<pem-file>
```
