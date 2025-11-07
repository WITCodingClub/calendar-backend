# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TermPolicy, type: :policy do
  include_examples "public-read resource policy", :term
end
