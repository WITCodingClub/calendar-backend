# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: term_elective_lists
#
#  id         :bigint           not null, primary key
#  body_text  :text
#  fetched_at :datetime         not null
#  school     :string
#  sha256     :string           not null
#  title      :string
#  url        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  term_id    :bigint           not null
#
# Indexes
#
#  index_term_elective_lists_on_term_id  (term_id)
#  index_term_elective_lists_on_url      (url) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id) ON DELETE => cascade
#
RSpec.describe TermElectiveList do
  subject { create(:term_elective_list) }

  it { is_expected.to belong_to(:term) }
  it { is_expected.to have_many(:courses).class_name("TermElectiveCourse").dependent(:delete_all) }
  it { is_expected.to validate_presence_of(:url) }
  it { is_expected.to validate_uniqueness_of(:url) }
  it { is_expected.to validate_presence_of(:sha256) }
  it { is_expected.to validate_presence_of(:fetched_at) }

  it "is deleted with its term" do
    list = create(:term_elective_list)

    expect { list.term.destroy }.to change(described_class, :count).by(-1)
  end
end
