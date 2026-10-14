# frozen_string_literal: true

require "rails_helper"

RSpec.describe SectionLink do
  it { is_expected.to belong_to(:course) }
  it { is_expected.to belong_to(:linked_course).class_name("Course") }
  it { is_expected.to validate_presence_of(:option_group) }
  it { is_expected.to validate_numericality_of(:option_group).only_integer.is_greater_than_or_equal_to(0) }
end
