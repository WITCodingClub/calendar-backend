# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_announcements
#
#  id                 :bigint           not null, primary key
#  body               :text
#  posted_at          :datetime
#  removed_at         :datetime
#  source_url         :string
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_announcements_on_course_offering_id  (course_offering_id)
#  index_brightspace_announcements_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
module Brightspace
  class AnnouncementSerializer
    def initialize(announcement)
      @announcement = announcement
    end

    def as_json(*)
      {
        id:         @announcement.public_id,
        source_id:  @announcement.source_id,
        title:      @announcement.title,
        body:       @announcement.body,
        source_url: @announcement.source_url,
        posted_at:  @announcement.posted_at&.utc&.iso8601
      }
    end
  end
end
