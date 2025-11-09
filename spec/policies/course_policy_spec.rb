# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePolicy, type: :policy do
  it_behaves_like "public-read resource policy", :course
end
