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
  private
    def self.query(name, deps, value = nil, &block)
      klass = Class.new(Attributes::QueryAttribute) do
        depends deps

        if block
          define_singleton_method(:select_value, &block)
        else
          define_singleton_method(:select_value) { value }
        end
      end
      attribute name, klass
    end
  end
end
