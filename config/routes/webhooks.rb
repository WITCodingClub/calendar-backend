# frozen_string_literal: true

# Requests that outside services send to us.

# Google RISC cross-account protection webhook
post "/risc/events", to: "webhooks/google_risc#create", as: :risc_events
