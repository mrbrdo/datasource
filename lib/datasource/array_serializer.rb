require "active_model/serializer"

module Datasource
  superclass = if defined?(ActiveModel::Serializer::ArraySerializer)
    ActiveModel::Serializer::ArraySerializer
  else
    ActiveModel::ArraySerializer
  end
  class ArraySerializer < superclass
    def initialize(objects, options = {})
      datasource_class = options.delete(:datasource)
      adapter = Datasource::Base.adapter
      if adapter.is_scope?(objects)
        datasource_class ||= adapter.scope_to_class(objects).default_datasource

        records = objects
          .with_datasource(datasource_class)
          .for_serializer(options[:serializer]).all.to_a # all needed for Sequel eager loading

        super(records, options)
      else
        super
      end
    end
  end
end
