# frozen_string_literal: true

# What goes on the calendar: the courses a user takes, how each event looks,
# and the university calendar events.
#
# Drawn inside namespace :api in config/routes/api.rb.

# Course processing
post "process_courses",       to: "courses#process_courses"
post "process_courses/batch", to: "courses#process_courses_batch"
post "courses/reprocess",     to: "courses#reprocess"

# Calendar preferences (global + per event-type + per university calendar category)
resources :calendar_preferences, only: [ :index, :show, :update, :destroy ] do
  collection { post :preview }
end

# Per-event preferences (meeting time or calendar event)
post "meeting_times/preferences", to: "event_preferences#batch_show"
resources :meeting_times, only: [] do
  resource :preference, controller: "event_preferences", only: [ :show, :update, :destroy ]
end
resources :calendar_events, only: [] do
  resource :preference, controller: "event_preferences", only: [ :show, :update, :destroy ]
end

# University calendar events
resources :university_calendar_events, only: [ :index, :show ] do
  collection do
    get  :categories
    get  :holidays
    post :sync
  end
end
