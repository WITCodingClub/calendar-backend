# frozen_string_literal: true

# app/services/application_service.rb
class ApplicationService
  class << self
    def call(*, **)
      new(*, **).call
    end

    def call!(*, **)
      new(*, **).call!
    end

  end

  def initialize(*, **); end

  def call
    raise NotImplementedError
  end

  def call!
    raise NotImplementedError
  end

end
