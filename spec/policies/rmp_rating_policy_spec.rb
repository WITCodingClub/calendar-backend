# frozen_string_literal: true

require "rails_helper"

RSpec.describe RmpRatingPolicy, type: :policy do
  it_behaves_like "public-read resource policy", :rmp_rating
end
