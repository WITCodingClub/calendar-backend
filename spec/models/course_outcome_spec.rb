# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: course_outcomes
#
#  id         :bigint           not null, primary key
#  crn        :integer          not null
#  outcome    :string           not null
#  term_uid   :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_course_outcomes_on_user_id_and_term_uid_and_crn  (user_id,term_uid,crn) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe CourseOutcome, type: :model do
  subject { create(:course_outcome) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:term_uid) }
  it { is_expected.to validate_presence_of(:crn) }
  it { is_expected.to validate_uniqueness_of(:crn).scoped_to(:user_id, :term_uid) }

  it do
    expect(subject).to define_enum_for(:outcome).with_values(described_class::OUTCOMES)
                                                .backed_by_column_of_type(:string).validating
  end
end
