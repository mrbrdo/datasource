module Datasource
  Error = Class.new(StandardError)
  RecursionError = Class.new(StandardError)

  def self.load(adapter = nil)
    unless adapter
      adapter = if defined? ActiveRecord
        :activerecord
      elsif defined? Sequel
        :sequel
      end
    end

    require 'datasource/adapters/active_record' if [:activerecord, :active_record].include?(adapter)
    require 'datasource/adapters/sequel' if adapter == :sequel
    require 'datasource/consumer_adapters/active_model_serializers' if defined? ActiveModel::Serializer
  end
end

require 'datasource/base'

require 'datasource/attributes/computed_attribute'
require 'datasource/attributes/query_attribute'
require 'datasource/attributes/loader'

require 'datasource/serializer'
