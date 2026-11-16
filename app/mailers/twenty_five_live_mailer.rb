# frozen_string_literal: true

class TwentyFiveLiveMailer < ApplicationMailer
  def constant_drift_notification(drifts)
    @drifts = drifts
    mail(
      to: Rails.application.config.x.maintainer_email,
      subject: "[WIT Calendar] 25Live constant data has changed — review required"
    )
  end
end
