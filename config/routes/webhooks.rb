# frozen_string_literal: true

post "/risc/events", to: "webhooks/google_risc#create", as: :risc_events
