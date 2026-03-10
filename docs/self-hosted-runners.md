# Self-Hosted Runners

This repository now assumes two isolated runner classes:

- `self-hosted,dev`
- `self-hosted,prod`

Production workflows must never run on the `dev` runner.

## Host requirements

- Linux host with Docker and git
- outbound access to GitHub
- access to the target environment only
- dedicated Unix user for runner, for example `github-runner`
- repository must be private

## Runner layout

Recommended directories:

- `/opt/actions-runner-dev`
- `/opt/actions-runner-prod`

Run one runner service per host unless you have a strong reason to multiplex.

## Registration flow

1. In GitHub open repository or organization settings.
2. Go to `Settings -> Actions -> Runners`.
3. Create a new self-hosted runner.
4. Choose Linux and the correct architecture.
5. Copy the generated shell commands and run them on the target host.

GitHub official docs:

- https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners
- https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service

## Dev runner

Register with labels:

- `self-hosted`
- `dev`

Example `config.sh` invocation:

```bash
./config.sh \
  --url https://github.com/<org-or-user>/<repo> \
  --token <one-hour-token> \
  --name infra-dev-runner-01 \
  --labels self-hosted,dev \
  --runnergroup Default \
  --work _work \
  --unattended
```

Install as a service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

## Prod runner

Register with labels:

- `self-hosted`
- `prod`

Example:

```bash
./config.sh \
  --url https://github.com/<org-or-user>/<repo> \
  --token <one-hour-token> \
  --name infra-prod-runner-01 \
  --labels self-hosted,prod \
  --runnergroup Default \
  --work _work \
  --unattended
```

Install as a service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

## Hard rules

- do not place prod runner on the same host as dev runner
- do not share SSH keys between dev and prod runner users
- do not share `INFRA_ENV_DEV` and `INFRA_ENV_PROD`
- restrict network egress/ingress per host to the required environment
- do not use broad labels like `linux` alone in workflow routing

## Validation

After registration:

1. confirm runner is visible in GitHub UI
2. confirm labels are correct
3. run a no-op workflow on each runner class
4. verify prod workflow is not eligible on `dev` runner and vice versa
