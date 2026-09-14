# frozen_string_literal: true

require "rails_helper"

RSpec.describe FinalsSchedule, type: :model do
  it { is_expected.to belong_to(:term) }
  it { is_expected.to belong_to(:uploaded_by).class_name("User") }

  it { is_expected.to validate_presence_of(:term) }
  it { is_expected.to validate_presence_of(:uploaded_by) }

  it do
    expect(subject).to define_enum_for(:status)
      .with_values(pending: 0, processing: 1, completed: 2, failed: 3)
      .backed_by_column_of_type(:integer)
      .with_default(:pending)
  end

  # #pdf_file_is_pdf only runs `if: -> { pdf_file.attached? }`, so it needs a
  # real ActiveStorage attachment rather than a one-liner.
end
