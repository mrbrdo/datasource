require "active_model/serializer"

module Datasource
  module ConsumerAdapters
    module ActiveModelSerializers
      module ArraySerializer
        def initialize_with_datasource(objects, options = {})
          datasource_class = options.delete(:datasource)
          adapter = Datasource.orm_adapters.find { |a| a.is_scope?(objects) }
          if adapter && !adapter.scope_loaded?(objects)
            datasource_class ||= adapter.scope_to_class(objects).default_datasource

            records = objects
              .with_datasource(datasource_class)
              .for_serializer(options[:serializer]).all.to_a # all needed for Sequel eager loading

            initialize_without_datasource(records, options)
          else
            initialize_without_datasource(objects, options)
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

      def to_datasource_select(result, klass, serializer = nil, serializer_assoc = nil, adapter = nil)
        adapter ||= Datasource::Base.default_adapter
        serializer ||= get_serializer_for(klass, serializer_assoc)
        result.unshift("*") if Datasource.config.simple_mode
        result.concat(serializer._attributes)
        result_assocs = {}
        result.push(result_assocs)

        serializer._associations.each_pair do |name, serializer_assoc|
          # TODO: what if assoc is renamed in serializer?
          reflection = adapter.association_reflection(klass, name.to_sym)
          assoc_class = reflection[:klass]

          name = name.to_s
          result_assocs[name] = []
          to_datasource_select(result_assocs[name], assoc_class, nil, serializer_assoc, adapter)
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
end

array_serializer_class = if defined?(ActiveModel::Serializer::ArraySerializer)
  ActiveModel::Serializer::ArraySerializer
else
  ActiveModel::ArraySerializer
end

array_serializer_class.class_exec do
  alias_method :initialize_without_datasource, :initialize
  include Datasource::ConsumerAdapters::ActiveModelSerializers::ArraySerializer
  def initialize(*args)
    initialize_with_datasource(*args)
  end
end
