module Datasource
  module Attributes
    class ComputedAttribute
      class << self
        attr_accessor :_depends

        def inherited(base)
          base._depends = (_depends || {}).dup # TODO: deep dup?
        end

        def depends(*args)
          args.each do |dep|
            _depends.deep_merge!(dep)
            dep.values.each do |names|
              Array(names).each do |name|
                define_method(name) do
                  @depend_values[name.to_s]
                end
              end
            end
          end
        end
      end

      def initialize(depend_values)
        @depend_values = depend_values
      end
    end
  end

  class Datasource::Base
    def self.computed_attribute(name, deps, &block)
      klass = Class.new(Attributes::ComputedAttribute) do
        depends deps

        define_method(:value, &block)
      end
      attribute name, klass
    end
  end
end
