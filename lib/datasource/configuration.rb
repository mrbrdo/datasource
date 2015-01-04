module Datasource
  module Configuration
    include ActiveSupport::Configurable
    extend ActiveSupport::Concern

    included do |base|
      base.config.adapters = Configuration.default_adapters
    end

    def self.default_adapters
      default_adapters = []
      if defined? ActiveRecord
        default_adapters.push(:activerecord)
      elsif defined? Sequel
        default_adapters.push(:sequel)
      end
      if defined? ActiveModel::Serializer
        default_adapters.push(:ams)
      end
    end
  end
end
