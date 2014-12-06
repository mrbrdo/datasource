require "active_model/serializer"

module Datasource
  module ConsumerAdapters
    module ActiveModelSerializers
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

    module_function
      def get_serializer_for(klass, serializer_assoc = nil)
        serializer = if serializer_assoc
          if serializer_assoc.kind_of?(Hash)
            serializer_assoc[:options].try(:[], :serializer)
          else
            serializer_assoc.options[:serializer]
          end
        end
        serializer || "#{klass.name}Serializer".constantize
      end

      def to_datasource_select(result, klass, serializer = nil, serializer_assoc = nil)
        serializer ||= get_serializer_for(klass, serializer_assoc)
        result.concat(serializer._attributes)
        result_assocs = {}
        result.push(result_assocs)

        serializer._associations.each_pair do |name, serializer_assoc|
          # TODO: what if assoc is renamed in serializer?
          reflection = Datasource::Base.adapter.association_reflection(klass, name.to_sym)
          assoc_class = reflection[:klass]

          name = name.to_s
          result_assocs[name] = []
          to_datasource_select(result_assocs[name], assoc_class, nil, serializer_assoc)
        end
      rescue Exception => ex
        if ex.is_a?(SystemStackError) || ex.is_a?(Datasource::RecursionError)
          fail Datasource::RecursionError, "recursive association (involving #{klass.name})"
        else
          raise
        end
      end
    end
  end
  ArrayAMS = ConsumerAdapters::ActiveModelSerializers::ArraySerializer
end
