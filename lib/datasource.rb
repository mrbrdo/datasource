module Datasource
  Error = Class.new(StandardError)
  RecursionError = Class.new(StandardError)

  AdapterPaths = {
    activerecord: 'datasource/adapters/active_record',
    active_record: :activerecord,
    sequel: 'datasource/adapters/sequel',
    ams: 'datasource/consumer_adapters/active_model_serializers',
    active_model_serializers: :ams
  }

  def self.load(*adapters)
    if adapters.empty?
      adapters = []
      if defined? ActiveRecord
        adapters.push(:activerecord)
      elsif defined? Sequel
        adapters.push(:sequel)
      end
      if defined? ActiveModel::Serializer
        adapters.push(:ams)
      end
    end

    adapters.each do |adapter|
      adapter = AdapterPaths[adapter]
      adapter = AdapterPaths[adapter] if adapter.is_a?(Symbol)
      require adapter
    end
  end
end

require 'datasource/base'

require 'datasource/attributes/computed_attribute'
require 'datasource/attributes/query_attribute'
require 'datasource/attributes/loader'

require 'datasource/serializer'
