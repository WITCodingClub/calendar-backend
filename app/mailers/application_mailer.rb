# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  has_history
  utm_params
  default from: "from@example.com"
  layout "mailer"

end
