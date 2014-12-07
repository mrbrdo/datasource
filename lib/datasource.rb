module Datasource
  Error = Class.new(StandardError)
end

require 'datasource/base'

require 'datasource/attributes/computed_attribute'
require 'datasource/attributes/query_attribute'
require 'datasource/attributes/loader'

require 'datasource/adapters/active_record' if defined? ActiveRecord
require 'datasource/adapters/sequel' if defined? Sequel

require 'datasource/array_serializer'
require 'datasource/serializer'
