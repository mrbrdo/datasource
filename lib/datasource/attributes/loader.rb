module Datasource
  module Attributes
    class Loader
      class << self
        attr_accessor :_options
        attr_accessor :_load_proc

        def inherited(base)
          base._options = (_options || {}).dup
        end

        def options(hash)
          self._options.merge!(hash)
        end

        def default_value
          self._options[:default]
        end

        def load(*args, &block)
          args = args.slice(0, _load_proc.arity) if _load_proc.arity >= 0
          results = _load_proc.call(*args, &block)

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
          elsif _options[:array_to_hash]
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
    def self.loader(name, _options = {}, &block)
      klass = Class.new(Attributes::Loader) do
        # depends deps
        options(_options)
        self._load_proc = block
      end
      @_loaders[name.to_sym] = klass
    end

    def self.loaded(name, _options = {}, &block)
      loader(name, _options, &block)
      orm_klass.class_eval do
        fail "#{name} already defined on #{to_s}, would be overridden by datasource loaded method" if method_defined?(name)
        define_method name do
          loaded_values[name.to_sym]
        end
      end
      computed name, loader: name
    end
  end
end
