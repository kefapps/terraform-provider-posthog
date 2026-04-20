# ANS-227 parity example

This example maps the current Ansyo acquisition and activation slice onto the
official PostHog Terraform provider resources:

- `posthog_feature_flag`
- `posthog_insight`
- `posthog_dashboard`
- `posthog_dashboard_layout`

The resource set matches the minimal parity target from `KEF-169`:

- flag `classic_questionnaires_enabled`
- dashboard `Acquisition & activation v1`
- insights `Registered users`, `Identified active users (28d)`,
  `Questionnaires created`, and
  `Owners with at least one questionnaire (28d)`

Known provider-native gaps still visible while keeping this implementation in
Terraform only:

- `posthog_feature_flag` does not expose a dedicated `description` field, so the
  current feature flag description cannot be expressed exactly.
- `posthog_dashboard_layout` does not expose tile display fields such as
  `show_description`, so the manifest's explicit `show_description = false`
  cannot currently be asserted from Terraform.

For local validation with the official provider workflow, the ignored
`playground/main.tf` in the repository root mirrors this example directly for
`make playground-plan` and `make playground-apply`.
