Rails.application.routes.draw do
  # Authentication routes (custom, no Devise)
  get "users/sign_in", to: "sessions#new", as: :new_user_session
  delete "users/sign_out", to: "sessions#destroy", as: :destroy_user_session
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    # Authentication
    post "login", to: "authentication#login"
    post "signup", to: "authentication#signup"
    post "request_magic_link", to: "authentication#request_magic_link"

    # Course events
    post "process_courses", to: "course#process_courses"
  end

  # ical / ics calendar
  get "/calendar/:calendar_token", to: "calendars#show", as: :calendar, defaults: { format: :ics }

  # google oauth2 callback
  get '/auth/google_oauth2/callback', to: 'auth#google'

  # temporary google auth test page
  get '/tmp/google', to: 'google_test#index'


  # Admin area with authentication constraint
  constraints AdminConstraint.new do
    namespace :admin do
      root to: "application#index"
      resources :users, only: [:index, :show, :edit, :update, :destroy]
      resources :calendars, only: [:index, :destroy]

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

  # User dashboard
  get "dashboard", to: "dashboard#index", as: :dashboard

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  mount OkComputer::Engine, at: "/healthchecks"

  # Magic link routes (HTML pages)
  post "request_magic_link", to: "magic_link#request_link"
  get "magic_link/verify", to: "magic_link#verify"
  get "magic_link/sent", to: "magic_link#sent"

  # Root route
  root to: "sessions#new"
end
