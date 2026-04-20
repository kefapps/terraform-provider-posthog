# Survey And Proxy Record Framing

This note captures the outcome of `KEF-171`: how the official PostHog Terraform
provider should approach the remaining Ansyo gaps around surveys and managed
reverse proxies.

## Outcome

The two missing surfaces should not be treated the same way.

- `posthog_survey` should become a first-class project-scoped resource.
- `posthog_proxy_record` should remain a follow-up design track until we have a
  safe acceptance strategy with disposable DNS automation.

## Evidence

### Surveys

The PostHog OpenAPI schema exposes a conventional project-scoped CRUD surface:

- `GET /api/projects/{project_id}/surveys/`
- `POST /api/projects/{project_id}/surveys/`
- `GET /api/projects/{project_id}/surveys/{id}/`
- `PUT /api/projects/{project_id}/surveys/{id}/`
- `PATCH /api/projects/{project_id}/surveys/{id}/`
- `DELETE /api/projects/{project_id}/surveys/{id}/`

The real API also accepts a minimal sandbox payload and returns a stable UUID:

```json
{
  "name": "KEF-171 survey probe ...",
  "type": "popover",
  "questions": [{ "type": "open", "question": "Probe question" }],
  "archived": false
}
```

That probe was successfully:

1. created,
2. retrieved by ID,
3. deleted,
4. confirmed absent with a `404` after deletion.

This is a normal Terraform-compatible lifecycle.

### Proxy records

The PostHog OpenAPI schema exposes an organization-scoped reverse proxy workflow:

- `GET /api/organizations/{organization_id}/proxy_records/`
- `POST /api/organizations/{organization_id}/proxy_records/`
- `GET /api/organizations/{organization_id}/proxy_records/{id}/`
- `DELETE /api/organizations/{organization_id}/proxy_records/{id}/`
- `POST /api/organizations/{organization_id}/proxy_records/{id}/retry/`

Notably, there is no `PUT` or `PATCH`.

The schema and real API responses both show the same model:

- `domain` is the only writable input
- `target_cname` is computed
- `status` is computed and async
- `message` is computed
- terminal and transient states include `waiting`, `issuing`, `valid`,
  `warning`, `erroring`, `deleting`, and `timed_out`

This is not a standard mutable resource. It is closer to an asynchronous
provisioning workflow whose correctness depends on external DNS ownership and
propagation.

## Recommended Terraform Shapes

### Recommended next implementation: `posthog_survey`

Recommended scope:

- project-scoped resource
- import format: `project_id/survey_uuid`

Recommended schema split:

- model stable scalar fields directly:
  - `name`
  - `description`
  - `type`
  - `schedule`
  - `linked_flag_id`
  - `linked_insight_id`
  - `start_date`
  - `end_date`
  - `archived`
  - `responses_limit`
  - `iteration_count`
  - `iteration_frequency_days`
  - `response_sampling_start_date`
  - `response_sampling_interval_type`
  - `response_sampling_interval`
  - `response_sampling_limit`
  - `enable_partial_responses`
  - `enable_iframe_embedding`
- model the complex bodies as normalized JSON strings:
  - `questions_json`
  - `conditions_json`
  - `appearance_json`
  - `translations_json`
  - `form_content_json`
  - `targeting_flag_filters_json`

Why JSON attributes are the safer upstream choice:

- the survey API surface is large and evolving
- questions are polymorphic
- read and write payloads differ because several fields are write-only
- this matches the provider's existing pattern of using normalized JSON for
  deeply nested objects when strong typing would create churn

Expected computed fields:

- `id`
- `created_at`
- `created_by`
- `linked_flag`
- `targeting_flag`
- `internal_targeting_flag`

Implementation note:

`posthog_survey` should use a custom resource instead of the generic resource
helper because the create/update payload differs from the read payload and
because several nested objects need JSON normalization to avoid import drift.

### Deferred track: `posthog_proxy_record`

Recommended scope if pursued later:

- organization-scoped resource
- import format: `organization_id/proxy_record_uuid`

Recommended lifecycle if implemented:

- `domain` as required input
- all other fields computed
- no in-place update support because the API has no update endpoint
- `domain` would effectively be `RequiresReplace`

Why this should not be the next provider implementation:

- correctness depends on external DNS changes outside Terraform provider control
- create is asynchronous and may remain `waiting` or become `timed_out`
- a meaningful acceptance test requires disposable domains plus automated DNS
  provisioning and cleanup
- the provider UX must decide whether `waiting` is acceptable state or a create
  failure that should time out

This should be treated as a design and test-harness problem before it becomes a
provider resource problem.

## Acceptance Strategy

### Survey

Safe acceptance coverage is feasible now on the existing PostHog sandbox:

1. create a minimal survey with one open question
2. read and verify stable fields
3. update at least one scalar field and one JSON field
4. import the survey and verify no drift
5. delete it

### Proxy record

Safe acceptance coverage is not feasible without extra infrastructure.

Required prerequisites:

- disposable organization-scoped subdomains
- automated DNS management in tests
- a deterministic polling contract for provisioning status
- explicit cleanup for partially provisioned proxies

## Decision

`KEF-171` should close with:

- a green light to create a dedicated implementation ticket for
  `posthog_survey`
- a separate follow-up ticket for `posthog_proxy_record` design and acceptance
  strategy, not immediate implementation
