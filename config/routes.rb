# frozen_string_literal: true

# == Route Map
#
# ======================================================================
# ✅ LogBench is ready to use!
# View your logs: log_bench log/development.log
# For help: log_bench --help
# ======================================================================
# Routes for application:
#                                   Prefix Verb   URI Pattern                                                                                       Controller#Action
#                               okcomputer        /okcomputer                                                                                       OkComputer::Engine
#                         new_user_session GET    /users/sign_in(.:format)                                                                          sessions#new
#                     destroy_user_session DELETE /users/sign_out(.:format)                                                                         sessions#destroy
#                       rails_health_check GET    /up(.:format)                                                                                     rails/health#show
#                         api_user_onboard POST   /api/user/onboard(.:format)                                                                       api/users#onboard
#                            api_user_gcal POST   /api/user/gcal(.:format)                                                                          api/users#request_g_cal
#                  api_user_gcal_add_email POST   /api/user/gcal/add_email(.:format)                                                                api/users#add_email_to_g_cal
#               api_user_gcal_remove_email DELETE /api/user/gcal/remove_email(.:format)                                                             api/users#remove_email_from_g_cal
#                       api_faculty_by_rmp GET    /api/faculty/by_rmp(.:format)                                                                     api/faculty#get_info_by_rmp_id
#                      api_process_courses POST   /api/process_courses(.:format)                                                                    api/courses#process_courses
#         preview_api_calendar_preferences POST   /api/calendar_preferences/preview(.:format)                                                       api/calendar_preferences#preview
#                 api_calendar_preferences GET    /api/calendar_preferences(.:format)                                                               api/calendar_preferences#index
#                  api_calendar_preference GET    /api/calendar_preferences/:id(.:format)                                                           api/calendar_preferences#show
#                                          PATCH  /api/calendar_preferences/:id(.:format)                                                           api/calendar_preferences#update
#                                          PUT    /api/calendar_preferences/:id(.:format)                                                           api/calendar_preferences#update
#                                          DELETE /api/calendar_preferences/:id(.:format)                                                           api/calendar_preferences#destroy
#              api_meeting_time_preference GET    /api/meeting_times/:meeting_time_id/preference(.:format)                                          api/event_preferences#show
#                                          PATCH  /api/meeting_times/:meeting_time_id/preference(.:format)                                          api/event_preferences#update
#                                          PUT    /api/meeting_times/:meeting_time_id/preference(.:format)                                          api/event_preferences#update
#                                          DELETE /api/meeting_times/:meeting_time_id/preference(.:format)                                          api/event_preferences#destroy
#     api_google_calendar_event_preference GET    /api/google_calendar_events/:google_calendar_event_id/preference(.:format)                        api/event_preferences#show
#                                          PATCH  /api/google_calendar_events/:google_calendar_event_id/preference(.:format)                        api/event_preferences#update
#                                          PUT    /api/google_calendar_events/:google_calendar_event_id/preference(.:format)                        api/event_preferences#update
#                                          DELETE /api/google_calendar_events/:google_calendar_event_id/preference(.:format)                        api/event_preferences#destroy
#                                 calendar GET    /calendar/:calendar_token(.:format)                                                               calendars#show {format: :ics}
#              auth_google_oauth2_callback GET    /auth/google_oauth2/callback(.:format)                                                            auth#google
#                            oauth_success GET    /oauth/success(.:format)                                                                          oauth#success
#                            oauth_failure GET    /oauth/failure(.:format)                                                                          oauth#failure
#                     admin_oauth_callback GET    /admin/oauth/callback(.:format)                                                                   admin/service_account#callback
#                               admin_root GET    /admin(.:format)                                                                                  admin/application#index
#       revoke_oauth_credential_admin_user DELETE /admin/users/:id/oauth_credentials/:credential_id(.:format)                                       admin/users#revoke_oauth_credential
#                   enable_beta_admin_user POST   /admin/users/:id/enable_beta(.:format)                                                            admin/users#enable_beta
#                  disable_beta_admin_user DELETE /admin/users/:id/disable_beta(.:format)                                                           admin/users#disable_beta
#                              admin_users GET    /admin/users(.:format)                                                                            admin/users#index
#                          edit_admin_user GET    /admin/users/:id/edit(.:format)                                                                   admin/users#edit
#                               admin_user GET    /admin/users/:id(.:format)                                                                        admin/users#show
#                                          PATCH  /admin/users/:id(.:format)                                                                        admin/users#update
#                                          PUT    /admin/users/:id(.:format)                                                                        admin/users#update
#                                          DELETE /admin/users/:id(.:format)                                                                        admin/users#destroy
#                          admin_calendars GET    /admin/calendars(.:format)                                                                        admin/calendars#index
#                           admin_calendar DELETE /admin/calendars/:id(.:format)                                                                    admin/calendars#destroy
#                       admin_beta_testers GET    /admin/beta_testers(.:format)                                                                     admin/beta_testers#index
#                                          POST   /admin/beta_testers(.:format)                                                                     admin/beta_testers#create
#                    new_admin_beta_tester GET    /admin/beta_testers/new(.:format)                                                                 admin/beta_testers#new
#                        admin_beta_tester DELETE /admin/beta_testers/:id(.:format)                                                                 admin/beta_testers#destroy
#              admin_service_account_index GET    /admin/service_account(.:format)                                                                  admin/service_account#index
#          admin_service_account_authorize GET    /admin/service_account/authorize(.:format)                                                        admin/service_account#authorize
#           admin_service_account_callback GET    /admin/service_account/callback(.:format)                                                         admin/service_account#callback
#             admin_service_account_revoke POST   /admin/service_account/revoke(.:format)                                                           admin/service_account#revoke
#               admin_mission_control_jobs        /admin/jobs                                                                                       MissionControl::Jobs::Engine
#                             admin_blazer        /admin/blazer                                                                                     Blazer::Engine
#                                                 /admin/flipper                                                                                    Flipper::UI
#                  admin_rails_performance        /admin/performance                                                                                RailsPerformance::Engine
#                         admin_audits1984        /admin/audits                                                                                     Audits1984::Engine
#                                    admin GET    /admin(.:format)                                                                                  redirect(301, /users/sign_in)
#                                          GET    /admin/*path(.:format)                                                                            redirect(301, /users/sign_in)
#                             unauthorized GET    /unauthorized(.:format)                                                                           errors#unauthorized
#                                          GET    /404(.:format)                                                                                    errors#not_found
#                        letter_opener_web        /letter_opener                                                                                    LetterOpenerWeb::Engine
#                              ok_computer        /healthchecks                                                                                     OkComputer::Engine
#                                     root GET    /                                                                                                 sessions#new
#                                 mailkick        /mailkick                                                                                         Mailkick::Engine
#                        rails_performance        /rails/performance                                                                                RailsPerformance::Engine
#         turbo_recede_historical_location GET    /recede_historical_location(.:format)                                                             turbo/native/navigation#recede
#         turbo_resume_historical_location GET    /resume_historical_location(.:format)                                                             turbo/native/navigation#resume
#        turbo_refresh_historical_location GET    /refresh_historical_location(.:format)                                                            turbo/native/navigation#refresh
#            rails_postmark_inbound_emails POST   /rails/action_mailbox/postmark/inbound_emails(.:format)                                           action_mailbox/ingresses/postmark/inbound_emails#create
#               rails_relay_inbound_emails POST   /rails/action_mailbox/relay/inbound_emails(.:format)                                              action_mailbox/ingresses/relay/inbound_emails#create
#            rails_sendgrid_inbound_emails POST   /rails/action_mailbox/sendgrid/inbound_emails(.:format)                                           action_mailbox/ingresses/sendgrid/inbound_emails#create
#      rails_mandrill_inbound_health_check GET    /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#health_check
#            rails_mandrill_inbound_emails POST   /rails/action_mailbox/mandrill/inbound_emails(.:format)                                           action_mailbox/ingresses/mandrill/inbound_emails#create
#             rails_mailgun_inbound_emails POST   /rails/action_mailbox/mailgun/inbound_emails/mime(.:format)                                       action_mailbox/ingresses/mailgun/inbound_emails#create
#           rails_conductor_inbound_emails GET    /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#index
#                                          POST   /rails/conductor/action_mailbox/inbound_emails(.:format)                                          rails/conductor/action_mailbox/inbound_emails#create
#        new_rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/new(.:format)                                      rails/conductor/action_mailbox/inbound_emails#new
#            rails_conductor_inbound_email GET    /rails/conductor/action_mailbox/inbound_emails/:id(.:format)                                      rails/conductor/action_mailbox/inbound_emails#show
# new_rails_conductor_inbound_email_source GET    /rails/conductor/action_mailbox/inbound_emails/sources/new(.:format)                              rails/conductor/action_mailbox/inbound_emails/sources#new
#    rails_conductor_inbound_email_sources POST   /rails/conductor/action_mailbox/inbound_emails/sources(.:format)                                  rails/conductor/action_mailbox/inbound_emails/sources#create
#    rails_conductor_inbound_email_reroute POST   /rails/conductor/action_mailbox/:inbound_email_id/reroute(.:format)                               rails/conductor/action_mailbox/reroutes#create
# rails_conductor_inbound_email_incinerate POST   /rails/conductor/action_mailbox/:inbound_email_id/incinerate(.:format)                            rails/conductor/action_mailbox/incinerates#create
#                       rails_service_blob GET    /rails/active_storage/blobs/redirect/:signed_id/*filename(.:format)                               active_storage/blobs/redirect#show
#                 rails_service_blob_proxy GET    /rails/active_storage/blobs/proxy/:signed_id/*filename(.:format)                                  active_storage/blobs/proxy#show
#                                          GET    /rails/active_storage/blobs/:signed_id/*filename(.:format)                                        active_storage/blobs/redirect#show
#                rails_blob_representation GET    /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename(.:format) active_storage/representations/redirect#show
#          rails_blob_representation_proxy GET    /rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename(.:format)    active_storage/representations/proxy#show
#                                          GET    /rails/active_storage/representations/:signed_blob_id/:variation_key/*filename(.:format)          active_storage/representations/redirect#show
#                       rails_disk_service GET    /rails/active_storage/disk/:encoded_key/*filename(.:format)                                       active_storage/disk#show
#                update_rails_disk_service PUT    /rails/active_storage/disk/:encoded_token(.:format)                                               active_storage/disk#update
#                     rails_direct_uploads POST   /rails/active_storage/direct_uploads(.:format)                                                    active_storage/direct_uploads#create
#                         actual_db_schema        /rails                                                                                            ActualDbSchema::Engine
#
# Routes for OkComputer::Engine:
#            Prefix Verb        URI Pattern       Controller#Action
#              root GET|OPTIONS /                 ok_computer/ok_computer#show {check: "default"}
# okcomputer_checks GET|OPTIONS /all(.:format)    ok_computer/ok_computer#index
#  okcomputer_check GET|OPTIONS /:check(.:format) ok_computer/ok_computer#show
#
# Routes for MissionControl::Jobs::Engine:
#                      Prefix Verb   URI Pattern                                                    Controller#Action
#     application_queue_pause DELETE /applications/:application_id/queues/:queue_id/pause(.:format) mission_control/jobs/queues/pauses#destroy
#                             POST   /applications/:application_id/queues/:queue_id/pause(.:format) mission_control/jobs/queues/pauses#create
#          application_queues GET    /applications/:application_id/queues(.:format)                 mission_control/jobs/queues#index
#           application_queue GET    /applications/:application_id/queues/:id(.:format)             mission_control/jobs/queues#show
#       application_job_retry POST   /applications/:application_id/jobs/:job_id/retry(.:format)     mission_control/jobs/retries#create
#     application_job_discard POST   /applications/:application_id/jobs/:job_id/discard(.:format)   mission_control/jobs/discards#create
#    application_job_dispatch POST   /applications/:application_id/jobs/:job_id/dispatch(.:format)  mission_control/jobs/dispatches#create
#    application_bulk_retries POST   /applications/:application_id/jobs/bulk_retries(.:format)      mission_control/jobs/bulk_retries#create
#   application_bulk_discards POST   /applications/:application_id/jobs/bulk_discards(.:format)     mission_control/jobs/bulk_discards#create
#             application_job GET    /applications/:application_id/jobs/:id(.:format)               mission_control/jobs/jobs#show
#            application_jobs GET    /applications/:application_id/:status/jobs(.:format)           mission_control/jobs/jobs#index
#         application_workers GET    /applications/:application_id/workers(.:format)                mission_control/jobs/workers#index
#          application_worker GET    /applications/:application_id/workers/:id(.:format)            mission_control/jobs/workers#show
# application_recurring_tasks GET    /applications/:application_id/recurring_tasks(.:format)        mission_control/jobs/recurring_tasks#index
#  application_recurring_task GET    /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#show
#                             PATCH  /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#update
#                             PUT    /applications/:application_id/recurring_tasks/:id(.:format)    mission_control/jobs/recurring_tasks#update
#                      queues GET    /queues(.:format)                                              mission_control/jobs/queues#index
#                       queue GET    /queues/:id(.:format)                                          mission_control/jobs/queues#show
#                         job GET    /jobs/:id(.:format)                                            mission_control/jobs/jobs#show
#                        jobs GET    /:status/jobs(.:format)                                        mission_control/jobs/jobs#index
#                        root GET    /                                                              mission_control/jobs/queues#index
#
# Routes for Blazer::Engine:
#            Prefix Verb   URI Pattern                       Controller#Action
#       run_queries POST   /queries/run(.:format)            blazer/queries#run
#    cancel_queries POST   /queries/cancel(.:format)         blazer/queries#cancel
#     refresh_query POST   /queries/:id/refresh(.:format)    blazer/queries#refresh
#    tables_queries GET    /queries/tables(.:format)         blazer/queries#tables
#    schema_queries GET    /queries/schema(.:format)         blazer/queries#schema
#      docs_queries GET    /queries/docs(.:format)           blazer/queries#docs
#           queries GET    /queries(.:format)                blazer/queries#index
#                   POST   /queries(.:format)                blazer/queries#create
#         new_query GET    /queries/new(.:format)            blazer/queries#new
#        edit_query GET    /queries/:id/edit(.:format)       blazer/queries#edit
#             query GET    /queries/:id(.:format)            blazer/queries#show
#                   PATCH  /queries/:id(.:format)            blazer/queries#update
#                   PUT    /queries/:id(.:format)            blazer/queries#update
#                   DELETE /queries/:id(.:format)            blazer/queries#destroy
#         run_check GET    /checks/:id/run(.:format)         blazer/checks#run
#            checks GET    /checks(.:format)                 blazer/checks#index
#                   POST   /checks(.:format)                 blazer/checks#create
#         new_check GET    /checks/new(.:format)             blazer/checks#new
#        edit_check GET    /checks/:id/edit(.:format)        blazer/checks#edit
#             check PATCH  /checks/:id(.:format)             blazer/checks#update
#                   PUT    /checks/:id(.:format)             blazer/checks#update
#                   DELETE /checks/:id(.:format)             blazer/checks#destroy
# refresh_dashboard POST   /dashboards/:id/refresh(.:format) blazer/dashboards#refresh
#        dashboards POST   /dashboards(.:format)             blazer/dashboards#create
#     new_dashboard GET    /dashboards/new(.:format)         blazer/dashboards#new
#    edit_dashboard GET    /dashboards/:id/edit(.:format)    blazer/dashboards#edit
#         dashboard GET    /dashboards/:id(.:format)         blazer/dashboards#show
#                   PATCH  /dashboards/:id(.:format)         blazer/dashboards#update
#                   PUT    /dashboards/:id(.:format)         blazer/dashboards#update
#                   DELETE /dashboards/:id(.:format)         blazer/dashboards#destroy
#              root GET    /                                 blazer/queries#home
#
# Routes for RailsPerformance::Engine:
#                        Prefix Verb URI Pattern             Controller#Action
#                  engine_asset GET  /assets/*file(.:format) Inline handler (Proc/Lambda)
#             rails_performance GET  /                       rails_performance/rails_performance#index
#    rails_performance_requests GET  /requests(.:format)     rails_performance/rails_performance#requests
#     rails_performance_crashes GET  /crashes(.:format)      rails_performance/rails_performance#crashes
#      rails_performance_recent GET  /recent(.:format)       rails_performance/rails_performance#recent
#        rails_performance_slow GET  /slow(.:format)         rails_performance/rails_performance#slow
#       rails_performance_trace GET  /trace/:id(.:format)    rails_performance/rails_performance#trace
#     rails_performance_summary GET  /summary(.:format)      rails_performance/rails_performance#summary
#     rails_performance_sidekiq GET  /sidekiq(.:format)      rails_performance/rails_performance#sidekiq
# rails_performance_delayed_job GET  /delayed_job(.:format)  rails_performance/rails_performance#delayed_job
#       rails_performance_grape GET  /grape(.:format)        rails_performance/rails_performance#grape
#        rails_performance_rake GET  /rake(.:format)         rails_performance/rails_performance#rake
#      rails_performance_custom GET  /custom(.:format)       rails_performance/rails_performance#custom
#   rails_performance_resources GET  /resources(.:format)    rails_performance/rails_performance#resources
#
# Routes for Audits1984::Engine:
#            Prefix Verb  URI Pattern                                Controller#Action
#    session_audits POST  /sessions/:session_id/audits(.:format)     audits1984/audits#create
#     session_audit PATCH /sessions/:session_id/audits/:id(.:format) audits1984/audits#update
#                   PUT   /sessions/:session_id/audits/:id(.:format) audits1984/audits#update
#          sessions GET   /sessions(.:format)                        audits1984/sessions#index
#           session GET   /sessions/:id(.:format)                    audits1984/sessions#show
# filtered_sessions PATCH /filtered_sessions(.:format)               audits1984/filtered_sessions#update
#                   PUT   /filtered_sessions(.:format)               audits1984/filtered_sessions#update
#              root GET   /                                          audits1984/sessions#index
#
# Routes for LetterOpenerWeb::Engine:
#        Prefix Verb URI Pattern                      Controller#Action
#       letters GET  /                                letter_opener_web/letters#index
# clear_letters POST /clear(.:format)                 letter_opener_web/letters#clear
#        letter GET  /:id(/:style)(.:format)          letter_opener_web/letters#show
# delete_letter POST /:id/delete(.:format)            letter_opener_web/letters#destroy
#               GET  /:id/attachments/:file(.:format) letter_opener_web/letters#attachment {file: /[^\/]+/}
#
# Routes for Mailkick::Engine:
#                   Prefix Verb     URI Pattern                              Controller#Action
# unsubscribe_subscription GET|POST /subscriptions/:id/unsubscribe(.:format) mailkick/subscriptions#unsubscribe
#   subscribe_subscription GET      /subscriptions/:id/subscribe(.:format)   mailkick/subscriptions#subscribe
#             subscription GET      /subscriptions/:id(.:format)             mailkick/subscriptions#show
#
# Routes for ActualDbSchema::Engine:
#                          Prefix Verb URI Pattern                                Controller#Action
#              rollback_migration POST /migrations/:id/rollback(.:format)         actual_db_schema/migrations#rollback
#               migrate_migration POST /migrations/:id/migrate(.:format)          actual_db_schema/migrations#migrate
#                      migrations GET  /migrations(.:format)                      actual_db_schema/migrations#index
#                       migration GET  /migrations/:id(.:format)                  actual_db_schema/migrations#show
#      rollback_phantom_migration POST /phantom_migrations/:id/rollback(.:format) actual_db_schema/phantom_migrations#rollback
# rollback_all_phantom_migrations POST /phantom_migrations/rollback_all(.:format) actual_db_schema/phantom_migrations#rollback_all
#              phantom_migrations GET  /phantom_migrations(.:format)              actual_db_schema/phantom_migrations#index
#               phantom_migration GET  /phantom_migrations/:id(.:format)          actual_db_schema/phantom_migrations#show
#           delete_broken_version POST /broken_versions/:id/delete(.:format)      actual_db_schema/broken_versions#delete
#      delete_all_broken_versions POST /broken_versions/delete_all(.:format)      actual_db_schema/broken_versions#delete_all
#                 broken_versions GET  /broken_versions(.:format)                 actual_db_schema/broken_versions#index
#                          schema GET  /schema(.:format)                          actual_db_schema/schema#index

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  get "users/sign_in", to: "sessions#new", as: :new_user_session
  delete "users/sign_out", to: "sessions#destroy", as: :destroy_user_session

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    post "user/onboard", to: "users#onboard"
    post "user/gcal", to: "users#request_g_cal"
    post "user/gcal/add_email", to: "users#add_email_to_g_cal"
    delete "user/gcal/remove_email", to: "users#remove_email_from_g_cal"

    get "faculty/by_rmp", to: "faculty#get_info_by_rmp_id"

    # Course events
    post "process_courses", to: "courses#process_courses"

    # Calendar preferences
    resources :calendar_preferences, only: [:index, :show, :update, :destroy] do
      collection do
        post :preview
      end
    end

    # Event preferences (per meeting time or calendar event)
    resources :meeting_times, only: [] do
      resource :preference, controller: 'event_preferences', only: [:show, :update, :destroy]
    end

    resources :google_calendar_events, only: [] do
      resource :preference, controller: 'event_preferences', only: [:show, :update, :destroy]
    end
  end

  get "/calendar/:calendar_token", to: "calendars#show", as: :calendar, defaults: { format: :ics }

  # google oauth2 callback
  get "/auth/google_oauth2/callback", to: "auth#google"

  # OAuth success/failure pages (for extension detection)
  get "/oauth/success", to: "oauth#success"
  get "/oauth/failure", to: "oauth#failure"

  # Admin OAuth callback for the service account
  get "/admin/oauth/callback", to: "admin/service_account#callback"

  # Admin area with authentication constraint
  constraints AdminConstraint.new do
    namespace :admin do
      root to: "application#index"
      resources :users, only: [:index, :show, :edit, :update, :destroy] do
        member do
          delete "oauth_credentials/:credential_id", to: "users#revoke_oauth_credential", as: :revoke_oauth_credential
          post :enable_beta, to: "users#enable_beta"
          delete :disable_beta, to: "users#disable_beta"
        end
      end
      resources :calendars, only: [:index, :destroy]
      resources :beta_testers, only: [:index, :new, :create, :destroy]

      # Service account OAuth management (owner only)
      get "service_account", to: "service_account#index", as: :service_account_index
      get "service_account/authorize", to: "service_account#authorize", as: :service_account_authorize
      get "service_account/callback", to: "service_account#callback", as: :service_account_callback
      post "service_account/revoke", to: "service_account#revoke", as: :service_account_revoke

      # Mounted engines
      mount MissionControl::Jobs::Engine, at: "jobs"
      mount Blazer::Engine, at: "blazer"
      mount Flipper::UI.app(Flipper), at: "flipper"
      mount RailsPerformance::Engine, at: "performance"
      mount Audits1984::Engine, at: "audits"
    end
  end

  # Fallback redirects if AdminConstraint fails
  get "admin", to: redirect("/users/sign_in")
  get "admin/*path", to: redirect("/users/sign_in")

  # Error pages
  get "unauthorized", to: "errors#unauthorized"
  get "404", to: "errors#not_found"

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  mount OkComputer::Engine, at: "/healthchecks"

  # Root route
  root to: "sessions#new"
end
