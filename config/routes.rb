# frozen_string_literal: true

Rails.application.routes.draw do
  get "health_check" => "application#health_check"

  root to: redirect("/forecast")

  get :forecast, to: "forecasts#show"
  get :pollutant_forecasts, to: "forecasts#pollutant_forecasts"
  get :alerts, to: "forecasts#alerts"
  resources :subscriptions
  get :resend_verification_code, to: "subscriptions#resend_verification_code"
  get :health_advice, to: "pages#health_advice"
  get :about, to: "pages#about"
  get :contact, to: "pages#contact"

  get :privacy_policy, to: "pages#privacy_policy"
  get :terms_and_conditions, to: "pages#terms_and_conditions"

  # If the CANONICAL_HOSTNAME env var is present, and the request doesn't come from that
  # hostname, redirect us to the canonical hostname with the path and query string present
  if ENV["CANONICAL_HOSTNAME"].present?
    constraints(host: Regexp.new("^(?!#{Regexp.escape(ENV["CANONICAL_HOSTNAME"])})")) do
      match "/(*path)" => redirect(host: ENV["CANONICAL_HOSTNAME"]), :via => [:all]
    end
  end
end
