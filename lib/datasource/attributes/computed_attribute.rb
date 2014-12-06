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
                define_attribute_reader(name)
              end
            end
          end
        end

      private
        def define_attribute_reader(attr_name)
          define_method(attr_name) do
            @depend_values[attr_name.to_s]
          end
        end
      end

      def initialize(depend_values, get_orm_object)
        @depend_values = depend_values
        @get_orm_object = get_orm_object
      end

    private
      def object
        @get_orm_object.call
      end
    end
  end

  class Datasource::Base
    def self.computed(name, deps, &block)
      klass = Class.new(Attributes::ComputedAttribute) do
        depends deps

        define_method(:value, &block)
      end
      attribute name, klass
    end
  end
end
