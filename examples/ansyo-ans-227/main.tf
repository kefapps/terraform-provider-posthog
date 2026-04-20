terraform {
  required_providers {
    posthog = {
      source = "posthog/posthog"
    }
  }
}

provider "posthog" {
  # Configuration can be provided via:
  # - Environment variables: POSTHOG_API_KEY, POSTHOG_PROJECT_ID, POSTHOG_HOST
  # - Or explicitly in the provider block:
  # api_key    = "your-api-key"
  # project_id = "12345"
  # host       = "https://us.posthog.com"
}

locals {
  acquisition_activation_tags = [
    "ansyo",
    "business-metrics",
    "acquisition",
    "activation",
  ]
}

resource "posthog_feature_flag" "classic_questionnaires_enabled" {
  key    = "classic_questionnaires_enabled"
  name   = "classic_questionnaires_enabled"
  active = true

  # The current provider exposes `name` and raw `filters`, but not a dedicated
  # feature flag description field.
  filters = jsonencode({
    groups = [{
      rollout_percentage = 0
    }]
  })
}

resource "posthog_dashboard" "acquisition_activation" {
  name        = "Acquisition & activation v1"
  description = "Repo-managed PostHog dashboard for acquisition and activation KPI v1: registrations, identified active users, questionnaire creation, and owners creating questionnaires."
  tags        = local.acquisition_activation_tags
}

resource "posthog_insight" "registered_users" {
  name        = "Registered users"
  description = "Daily trend of accounts becoming usable in Ansyo via the canonical user_registered event over the last 28 days."
  tags        = local.acquisition_activation_tags

  query_json = jsonencode({
    kind = "TrendsQuery"
    dateRange = {
      date_from = "-28d"
    }
    interval = "day"
    series = [{
      kind  = "EventsNode"
      event = "user_registered"
      name  = "user_registered"
    }]
    trendsFilter = {
      display    = "ActionsLineGraph"
      showLegend = false
    }
  })

  dashboard_ids = [posthog_dashboard.acquisition_activation.id]
  depends_on    = [posthog_dashboard.acquisition_activation]
}

resource "posthog_insight" "identified_active_users_28d" {
  name        = "Identified active users (28d)"
  description = "Unique identified distinct_id with at least one acquisition or activation business event over the rolling last 28 days."
  tags        = local.acquisition_activation_tags

  query_json = jsonencode({
    kind    = "DataVisualizationNode"
    display = "BoldNumber"
    source = {
      kind  = "HogQLQuery"
      query = "SELECT uniq(distinct_id) AS value FROM events WHERE distinct_id IS NOT NULL AND distinct_id != '' AND event IN ('user_registered', 'questionnaire_creation_started', 'questionnaire_creation_auth_required', 'questionnaire_created', 'questionnaire_created_duo', 'answer_started', 'answer_submitted', 'answer_submitted_duo', 'first_answer_submitted', 'guest_response_claimed', 'duo_synthesis_viewed', 'duo_synthesis_dwell_20s') AND timestamp >= now() - INTERVAL 28 DAY"
    }
  })

  dashboard_ids = [posthog_dashboard.acquisition_activation.id]
  depends_on    = [posthog_dashboard.acquisition_activation]
}

resource "posthog_insight" "questionnaires_created" {
  name        = "Questionnaires created"
  description = "Daily trend of questionnaire_created emissions over the last 28 days."
  tags = [
    "ansyo",
    "business-metrics",
    "activation",
  ]

  query_json = jsonencode({
    kind = "TrendsQuery"
    dateRange = {
      date_from = "-28d"
    }
    interval = "day"
    series = [{
      kind  = "EventsNode"
      event = "questionnaire_created"
      name  = "questionnaire_created"
    }]
    trendsFilter = {
      display    = "ActionsLineGraph"
      showLegend = false
    }
  })

  dashboard_ids = [posthog_dashboard.acquisition_activation.id]
  depends_on    = [posthog_dashboard.acquisition_activation]
}

resource "posthog_insight" "owners_with_at_least_one_questionnaire_28d" {
  name        = "Owners with at least one questionnaire (28d)"
  description = "Unique identified owners who created at least one questionnaire over the rolling last 28 days."
  tags = [
    "ansyo",
    "business-metrics",
    "activation",
  ]

  query_json = jsonencode({
    kind    = "DataVisualizationNode"
    display = "BoldNumber"
    source = {
      kind  = "HogQLQuery"
      query = "SELECT uniq(distinct_id) AS value FROM events WHERE event = 'questionnaire_created' AND distinct_id IS NOT NULL AND distinct_id != '' AND timestamp >= now() - INTERVAL 28 DAY"
    }
  })

  dashboard_ids = [posthog_dashboard.acquisition_activation.id]
  depends_on    = [posthog_dashboard.acquisition_activation]
}

resource "posthog_dashboard_layout" "acquisition_activation" {
  dashboard_id = posthog_dashboard.acquisition_activation.id

  tiles = [
    {
      insight_id = posthog_insight.identified_active_users_28d.id
      layouts_json = jsonencode({
        sm = { x = 0, y = 0, w = 6, h = 4 }
        xs = { x = 0, y = 0, w = 6, h = 4 }
      })
    },
    {
      insight_id = posthog_insight.owners_with_at_least_one_questionnaire_28d.id
      layouts_json = jsonencode({
        sm = { x = 6, y = 0, w = 6, h = 4 }
        xs = { x = 0, y = 4, w = 6, h = 4 }
      })
    },
    {
      insight_id = posthog_insight.registered_users.id
      layouts_json = jsonencode({
        sm = { x = 0, y = 4, w = 6, h = 5 }
        xs = { x = 0, y = 8, w = 6, h = 5 }
      })
    },
    {
      insight_id = posthog_insight.questionnaires_created.id
      layouts_json = jsonencode({
        sm = { x = 6, y = 4, w = 6, h = 5 }
        xs = { x = 0, y = 13, w = 6, h = 5 }
      })
    },
  ]

  # Tile ordering and placement must remain aligned with the attached insights.
  depends_on = [
    posthog_insight.registered_users,
    posthog_insight.identified_active_users_28d,
    posthog_insight.questionnaires_created,
    posthog_insight.owners_with_at_least_one_questionnaire_28d,
  ]
}

output "ansyo_ans_227_feature_flag_id" {
  description = "Feature flag ID for classic_questionnaires_enabled."
  value       = posthog_feature_flag.classic_questionnaires_enabled.id
}

output "ansyo_ans_227_dashboard_id" {
  description = "Dashboard ID for Acquisition & activation v1."
  value       = posthog_dashboard.acquisition_activation.id
}

output "ansyo_ans_227_insight_ids" {
  description = "Insight IDs keyed by the ANS-227 slice names."
  value = {
    registered_users                           = posthog_insight.registered_users.id
    identified_active_users_28d                = posthog_insight.identified_active_users_28d.id
    questionnaires_created                     = posthog_insight.questionnaires_created.id
    owners_with_at_least_one_questionnaire_28d = posthog_insight.owners_with_at_least_one_questionnaire_28d.id
  }
}
