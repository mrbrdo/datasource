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
      if @objects = objects.kind_of?(ActiveRecord::Relation)
        datasource_class ||= objects.klass.default_datasource

        records = objects
          .with_datasource(datasource_class)
          .for_serializer(options[:serializer]).to_a

        super(records, options)
      else
        super
      end
    end
  end
end
