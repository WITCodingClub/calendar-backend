# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeacherRatingTagPolicy, type: :policy do
  it_behaves_like "public-read resource policy", :teacher_rating_tag
end
