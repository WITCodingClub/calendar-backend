# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockboxAuditPolicy, type: :policy do
  it_behaves_like "admin-only resource policy", :lockbox_audit
end
