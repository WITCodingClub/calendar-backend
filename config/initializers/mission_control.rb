Rails.application.configure do
  # Use custom authentication instead of HTTP Basic Auth
  config.mission_control.jobs.base_controller_class = "Admin::BaseController"
  config.mission_control.jobs.http_basic_auth_enabled = false
end
