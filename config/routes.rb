Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # API routes
  namespace :api do
    # Authentication
    post "login", to: "authentication#login"
    post "signup", to: "authentication#signup"
    post "request_magic_link", to: "authentication#request_magic_link"

    # Course events
    post "process_events", to: "course_events#process_events"
  end

  namespace :admin do
    root to: "application#index"

    mount Blazer::Engine, at: "blazer", constraints: ->(request) {
      user = User.find_by(id: request.session[:user_id])
      user && AdminPolicy.new(user, :admin).blazer?
    }

    mount Flipper::UI.app(Flipper), at: "flipper", constraints: ->(request) {
      user = User.find_by(id: request.session[:user_id])
      user && AdminPolicy.new(user, :admin).flipper?
    }

    mount RailsPerformance::Engine, at: "performance", constraints: ->(request) {
      user = User.find_by(id: request.session[:user_id])
      user && AdminPolicy.new(user, :admin).access_admin_endpoints?
    }

    mount Audits1984::Engine, at: "audits", constraints: ->(request) {
      user = User.find_by(id: request.session[:user_id])
      user && AdminPolicy.new(user, :admin).access_admin_endpoints?
    }

    resources :users, shallow: true
  end

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  mount OkComputer::Engine, at: "/healthchecks"

  # Magic link verification (HTML page)
  get "magic_link/verify", to: "magic_link#verify"

  # Defines the root path route ("/")
  # root "posts#index"
end
