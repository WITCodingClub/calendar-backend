module CalendarTokenable
  extend ActiveSupport::Concern

  def cal_url
    "#{Rails.application.routes.url_helpers.root_url}/calendar/#{calendar_token}.ics"
  end

  def generate_calendar_token
    if calendar_token.blank?
      self.calendar_token = SecureRandom.urlsafe_base64(32)
      save!
    end
  end
end
