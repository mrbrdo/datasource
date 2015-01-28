require 'datasource/configuration'
module Datasource
  Error = Class.new(StandardError)
  RecursionError = Class.new(StandardError)
  include Configuration

  AdapterPaths = {
    activerecord: 'datasource/adapters/active_record',
    active_record: :activerecord,
    sequel: 'datasource/adapters/sequel',
    ams: 'datasource/consumer_adapters/active_model_serializers',
    active_model_serializers: :ams
  }

module_function
  def load(*adapters)
    unless adapters.empty?
      warn "[DEPRECATION] passing adapters to Datasource.load is deprecated. Use Datasource.setup instead."
      config.adapters = adapters
    end

    config.adapters.each do |adapter|
      adapter = AdapterPaths[adapter]
      adapter = AdapterPaths[adapter] if adapter.is_a?(Symbol)
      require adapter
    end
  end

  def setup
    yield(config)
    load
  end

  def orm_adapters
    @orm_adapters ||= begin
      Datasource::Adapters.constants.map { |name| Datasource::Adapters.const_get(name) }
    end
  end
end

require 'datasource/collection_context'
require 'datasource/base'

require 'datasource/attributes/computed_attribute'
require 'datasource/attributes/query_attribute'
require 'datasource/attributes/loaded'
