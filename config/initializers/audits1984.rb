# frozen_string_literal: true

# User has no #name attribute, so show auditors by full name. This file loads
# after the engine reads config.audits1984, so set the module directly.
Audits1984.auditor_name_attribute = :full_name
