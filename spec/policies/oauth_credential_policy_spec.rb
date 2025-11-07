# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OauthCredentialPolicy, type: :policy do
  include_examples "user-owned resource policy", :oauth_credential
end
