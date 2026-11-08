# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: finals_schedules
#
#  id             :bigint           not null, primary key
#  error_message  :text
#  processed_at   :datetime
#  stats          :jsonb
#  status         :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#  uploaded_by_id :bigint
#
# Indexes
#
#  index_finals_schedules_on_term_id_and_created_at  (term_id,created_at)
#  index_finals_schedules_on_uploaded_by_id          (uploaded_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (uploaded_by_id => users.id)
#
RSpec.describe FinalsSchedule, type: :model do
  it { is_expected.to belong_to(:term) }

  it { is_expected.to validate_presence_of(:term) }
  it { is_expected.to validate_presence_of(:uploaded_by).on(:create) }

  context "when saved" do
    # The uploader is required only on create (see the presence matcher above).
    # A saved schedule keeps working after its uploader's account is deleted.
    subject { create(:finals_schedule) }

    it { is_expected.to belong_to(:uploaded_by).class_name("User").optional }
  end

  it do
    expect(subject).to define_enum_for(:status)
      .with_values(pending: 0, processing: 1, completed: 2, failed: 3)
      .backed_by_column_of_type(:integer)
      .with_default(:pending)
  end

  describe "#trigger_calendar_resyncs_for_term" do
    it "queues a bulk sync for each Google user in the term" do
      schedule = create(:finals_schedule)
      user = create(:user)
      create(:course_calendar, oauth_credential: create(:oauth_credential, user: user, provider: "google"))
      create(:enrollment, user: user, course: create(:course, term: schedule.term))

      expect { schedule.trigger_calendar_resyncs_for_term }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).on_queue("default").at_priority(CourseCalendars::SyncJob::BULK_PRIORITY)
    end

    it "puts the syncs in a batch that the schedule finds again" do
      schedule = create(:finals_schedule)

      schedule.trigger_calendar_resyncs_for_term

      expect(schedule.resync_batch.metadata[:reason]).to eq("finals")
    end
  end

  # #pdf_file_is_pdf only runs `if: -> { pdf_file.attached? }`, so it needs a
  # real ActiveStorage attachment rather than a one-liner.
end
