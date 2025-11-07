# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LockboxAuditPolicy, type: :policy do
  include_examples "admin-only resource policy", :lockbox_audit
end
