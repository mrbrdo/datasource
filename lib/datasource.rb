require 'datasource/base'

require 'datasource/attributes/computed_attribute'
require 'datasource/attributes/query_attribute'

require 'datasource/adapters/active_record' if defined? ActiveRecord
require 'datasource/adapters/sequel' if defined? Sequel

require 'datasource/serializer'
