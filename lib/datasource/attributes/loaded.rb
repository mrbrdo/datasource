module Datasource
  module Attributes
    class Loaded
      class << self
        attr_accessor :_options

        def inherited(base)
          base._options = (_options || {}).dup
        end

        def options(hash)
          self._options.merge!(hash)
        end

        def default_value
          self._options[:default]
        end

        def load(collection_context)
          loader = collection_context.method(_options[:source])
          args = [collection_context].slice(0, loader.arity) if loader.arity >= 0
          results = loader.call(*args)

          if _options[:group_by]
            results = Array(results)
            send_args = if results.first && results.first.kind_of?(Hash)
              [:[]]
            else
              []
            end

            if _options[:one]
              results.inject({}) do |hash, r|
                key = r.send(*send_args, _options[:group_by])
                hash[key] = r
                hash
              end
            else
              results.inject({}) do |hash, r|
                key = r.send(*send_args, _options[:group_by])
                (hash[key] ||= []).push(r)
                hash
              end
            end
          elsif _options[:from] == :array
            Array(results).inject({}) do |hash, r|
              hash[r[0]] = r[1]
              hash
            end
          else
            results
          end
        end
      end
    end
  end

  class Datasource::Base
  private
    def self.loaded(name, _options = {}, &block)
      name = name.to_sym
      datasource_class = self
      loader_class = Class.new(Attributes::Loaded) do
        options(_options.reverse_merge(source: :"load_#{name}"))
      end
      @_loaders[name] = loader_class

      method_module = Module.new do
        define_method name do |*args, &block|
          if _datasource_loaded
            if _datasource_loaded.key?(name)
              _datasource_loaded[name]
            else
              fail Datasource::Error, "loader #{name} called but was not selected"
            end
          elsif defined?(super)
            super(*args, &block)
          else
            method_missing(name, *args, &block)
          end
        end
      end

      orm_klass.class_eval do
        prepend method_module
      end
      computed name, loader: name
    end
  end
end
