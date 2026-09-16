# frozen_string_literal: true

# Settings and OmniAuth auth hashes for "Sign in with Microsoft" specs. All
# values are synthetic.
module MicrosoftSignInHelpers
  TEST_TENANT_ID  = "0c0ffee0-0000-4000-8000-000000000001"
  OTHER_TENANT_ID = "0c0ffee0-0000-4000-8000-000000000002"

  # Stubs the three environment variables. Pass nil to leave one unset, so a
  # developer's own shell values never leak into a spec.
  def configure_microsoft_sign_in(client_id: "test-client-id", client_secret: "test-client-secret",
                                  tenant_id: TEST_TENANT_ID)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MICROSOFT_CLIENT_ID").and_return(client_id)
    allow(ENV).to receive(:[]).with("MICROSOFT_CLIENT_SECRET").and_return(client_secret)
    allow(ENV).to receive(:[]).with("MICROSOFT_TENANT_ID").and_return(tenant_id)
  end

  # The shape that omniauth-entra-id builds from the ID token claims.
  def microsoft_auth_hash(email:, oid:, tid: TEST_TENANT_ID, idp: nil, first_name: "Test", last_name: "Student")
    OmniAuth::AuthHash.new(
      provider:    "microsoft",
      uid:         "#{tid}#{oid}",
      info:        { email: email, first_name: first_name, last_name: last_name, name: "#{first_name} #{last_name}" },
      credentials: { token: "synthetic-access-token", expires_at: 1.hour.from_now.to_i },
      extra:       { raw_info: { "tid" => tid, "oid" => oid, "preferred_username" => email, "idp" => idp }.compact }
    )
  end
end

RSpec.configure do |config|
  config.include MicrosoftSignInHelpers
end
