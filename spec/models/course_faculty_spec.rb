# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseFaculty, type: :model do
  it { is_expected.to belong_to(:course) }
  it { is_expected.to belong_to(:faculty) }
end
