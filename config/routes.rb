# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users,
             controllers: { sessions: "users/sessions" },
             skip: [ :registrations ]

  get "up" => "rails/health#show", as: :rails_health_check

  draw :auth
  draw :site
  draw :feeds
  draw :webhooks
  draw :api
  draw :dashboard
  draw :admin

  get "unauthorized", to: "errors#unauthorized"
  get "404",          to: "errors#not_found"
  get "422",          to: "errors#unprocessable_entity"
  get "500",          to: "errors#internal_server_error"

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  mount OkComputer::Engine, at: "/healthchecks"

  root to: "home#index"
end
