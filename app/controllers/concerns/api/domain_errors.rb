# frozen_string_literal: true

module Api
  # The errors of shared services that any API action can meet, each with its
  # status. An action does not rescue them itself. AcademicProfiles::Error
  # covers every degree planning error, CourseOutcomes::InvalidOutcomesError
  # too, with its code.
  module DomainErrors
    extend ActiveSupport::Concern

    included do
      rescue_from Courses::InvalidPayloadError, with: :render_bad_request
      rescue_from FriendMeetings::Error, with: :render_unprocessable
      rescue_from AcademicProfiles::Error, with: :render_unprocessable
      rescue_from Catalog::BannerThrottle::CooldownError, with: :render_banner_unavailable
    end

    private

    def render_unprocessable(error)
      render_error error.message, status: :unprocessable_content, code: error.try(:code)
    end

    # Banner stopped answering a moment ago (Catalog::BannerThrottle), so the
    # request fails at once instead of waiting. This is expected, not a bug, so
    # it is not reported. The client can try again after Retry-After.
    def render_banner_unavailable(error)
      response.headers["Retry-After"] = error.retry_after.to_s
      render_error "Course data is not available right now. Try again in a few minutes.",
                   status: :service_unavailable, code: "BANNER_UNAVAILABLE"
    end
  end
end
