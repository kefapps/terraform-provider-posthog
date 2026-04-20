# Terraform Provider for PostHog

Terraform provider for managing [PostHog](https://posthog.com) resources.

## Documentation

For usage documentation and supported resources, see the [Terraform Registry](https://registry.terraform.io/providers/posthog/posthog/latest/docs).

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [Go](https://golang.org/doc/install) >= 1.24

## Building the Provider

```shell
go install
```

## Local Development

The `playground/` directory lets you test provider changes locally without publishing.

### Setup

1. Create your Terraform config in `playground/` (e.g., `playground/demo.tf`)

2. Build the provider and run terraform:

```shell
# Plan changes
make playground-plan

# Apply changes
make playground-apply
```

This builds the provider binary and configures Terraform to use your local build via `dev_overrides` - no `terraform init` required.

### Local secrets with 1Password CLI

This repository can be driven directly from environment variables loaded by
1Password CLI with `op://` secret references.

Two local files are used:

- `.op-bootstrap.env`: raw values you fill once locally, then sync into 1Password
- `.env`: runtime `op://` references generated from the synced 1Password item

Bootstrap flow:

1. Fill `.op-bootstrap.env` with the real PostHog values.
2. Run `make onepassword-sync` to create or update the matching 1Password item and generate `.env`.
3. Run provider commands through `op run --env-file=.env -- ...`.

```shell
# Verify that 1Password CLI is signed in
op whoami

# Create/update the 1Password item and generate .env
make onepassword-sync

# Validate the ANS-227 playground config against your PostHog dev project
op run --env-file=.env -- make playground-plan

# Apply the playground config
op run --env-file=.env -- make playground-apply

# Run acceptance tests
op run --env-file=.env -- make testacc
```

The process environment names expected by the provider are:

- `POSTHOG_API_KEY`
- `POSTHOG_PROJECT_ID`
- `POSTHOG_HOST`
- `POSTHOG_ORGANIZATION_ID`
- `POSTHOG_TEST_USER_EMAIL` for the acceptance tests that require an existing organization member

### Manual Setup

If you prefer to test outside the playground directory:

```shell
# Build the provider
make playground-binary

# Point Terraform to your local build
export TF_CLI_CONFIG_FILE=/path/to/terraform-provider-posthog/playground/terraformrc

# Run terraform commands in any directory
terraform plan
terraform apply
```

### Cleanup

```shell
make playground-clean
```

## Testing

### Unit Tests

```shell
go test ./...
```

### Local SonarQube Quality Gate

If you have a local SonarQube stack running on Docker, you can certify the
current provider worktree against it with:

```shell
make quality-bootstrap
make quality-sonar
```

The local bootstrap mirrors the pattern used in `../keftionnaire`:

- it persists SonarQube local state in a generated `.env.local` outside the repo
- it reuses the existing local Docker Sonar stack when available
- if a sibling `../keftionnaire` bootstrap state exists, it can seed admin
  access from it and generate a provider-specific scanner token automatically

Useful commands:

```shell
# Show the generated env path and current local Sonar settings
make quality-status

# Recreate the local provider Sonar bootstrap state
make quality-reset
make quality-bootstrap
```

`make quality-sonar` generates `coverage.out`, waits for the quality gate
result, and, on non-`main` branches, publishes a branch analysis with `main` as
the new-code reference branch by default.

### Acceptance Tests

Acceptance tests run against a real PostHog instance and create actual resources:

```shell
export POSTHOG_API_KEY="your-api-key"
export POSTHOG_PROJECT_ID="12345"
export POSTHOG_HOST="https://us.posthog.com"
export POSTHOG_ORGANIZATION_ID="your-org-uuid"   # Default for organization-scoped resources
export POSTHOG_TEST_USER_EMAIL="user@example.com" # Email of existing org member for membership tests (not the one who owns the token)

make testacc
```

## Generating Documentation

```shell
make generate
```

## Releasing

Releases are automated via GoReleaser when a signed tag is pushed. The Makefile provides convenience targets:

```shell
# Alpha releases (pre-release, for early testing)
make release-alpha VERSION=1.0.0 NUM=1  # creates v1.0.0-alpha.1

# Beta releases (pre-release, feature complete)
make release-beta VERSION=1.0.0 NUM=1   # creates v1.0.0-beta.1

# Stable releases
make release VERSION=1.0.0              # creates v1.0.0
```

**Requirements:**
- GPG key configured for signing (`git tag -s`)
- GPG key added to your GitHub account (for the "Verified" badge)

Pre-release versions (alpha, beta) won't be installed by default - users must explicitly pin to them in their Terraform configuration.

## License

See [LICENSE](LICENSE).
