# frozen_string_literal: true

class TwentyFiveLiveMailer < ApplicationMailer
  ADMIN_EMAIL = "mayonej@wit.edu"

  def constant_drift_notification(drifts)
    @drifts = drifts
    mail(
      to: ADMIN_EMAIL,
      subject: "[WIT Calendar] 25Live constant data has changed — review required"
    )
  end
end
