# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredentialPolicy, type: :policy do
  it_behaves_like "user-owned resource policy", :oauth_credential
end
