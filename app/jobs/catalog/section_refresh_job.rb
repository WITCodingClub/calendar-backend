# frozen_string_literal: true

module Catalog
  # Asks Banner again about the sections of one schedule, after
  # Courses::Processor answered from the stored catalog. The student gets the
  # answer at once, and a seat count or room change since the nightly sync
  # reaches the calendar a little later.
  class SectionRefreshJob < ApplicationJob
    queue_as :default

    # Banner stopped answering. The sections stay as the nightly sync left
    # them, so try again after each cooldown for a short time, then give up.
    include Catalog::BannerCooldownRetry
    retry_banner_cooldown within: 15.minutes

    def perform(course_ids)
      Catalog::SectionSync.call_many(course_ids)
    end
  end
end
