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

    # Course events
    post "process_courses", to: "courses#process_courses"
  end


  # google oauth2 callback
  get '/auth/google_oauth2/callback', to: 'auth#google'

  # Admin OAuth callback for the service account
  get '/admin/oauth/callback', to: 'admin/service_account#callback'

  # Admin area with authentication constraint
  constraints AdminConstraint.new do
    namespace :admin do
      root to: "application#index"
      resources :users, only: [:index, :show, :edit, :update, :destroy]
      resources :calendars, only: [:index, :destroy]

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
