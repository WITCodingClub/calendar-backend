# frozen_string_literal: true

require "rails_helper"

# Issue #684: the catalog `q` filter matches ILIKE '%q%' on three course
# columns. The migration builds trigram indexes concurrently, which cannot run
# inside the test transaction, so these examples check the schema that the
# migration leaves.
RSpec.describe "Trigram indexes on courses" do # rubocop:disable RSpec/DescribeClass
  let(:connection) { ActiveRecord::Base.connection }

  it "enables pg_trgm" do
    expect(connection.extension_enabled?("pg_trgm")).to be(true)
  end

  it "adds a GIN trigram index for each searched column" do
    indexes = connection.indexes(:courses).index_by(&:name)

    expect(indexes["index_courses_on_title_trgm"]).to have_attributes(using: :gin, opclasses: :gin_trgm_ops)
    expect(indexes["index_courses_on_subject_trgm"]).to have_attributes(using: :gin, opclasses: :gin_trgm_ops)
    expect(indexes["index_courses_on_course_number_text_trgm"]).to have_attributes(using: :gin)
  end
end
