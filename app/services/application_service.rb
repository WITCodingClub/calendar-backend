# frozen_string_literal: true

# A service object: X.call(...) builds X with the arguments and runs #call.
# X.call! runs #call!, which raises where #call returns a failure.
class ApplicationService
  def self.call(...) = new(...).call
  def self.call!(...) = new(...).call!
end
