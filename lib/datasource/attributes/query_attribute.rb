module Datasource
  module Attributes
    class QueryAttribute
      class << self
        attr_accessor :_depends

        def inherited(base)
          base._depends = (_depends || []).dup
        end

        def depends(*args)
          self._depends += args.map(&:to_s)
        end
      end
    end
  end

  class Datasource::Base
    def self.query_attribute(name, deps, &block)
      klass = Class.new(Attributes::QueryAttribute) do
        depends deps

        define_method(:select_value, &block)
      end
      attribute name, klass
    end
  end
end
