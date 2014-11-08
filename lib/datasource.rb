require 'datasource/adapters/active_record'

module Datasource
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

  class Base

    class << self
      attr_accessor :_attributes, :_virtual_attributes, :_associations
      attr_accessor :adapter

      def inherited(base)
        base._attributes = (_attributes || []).dup
        @adapter ||= Datasource::Adapters::ActiveRecord
        self.send :include, @adapter
      end

      def attributes(*attrs)
        attrs.each { |name| attribute(name) }
      end

      def attribute(name, klass = nil)
        @_attributes.push name: name.to_s, klass: klass
      end

      def includes_many(name, klass, foreign_key)
        @_attributes.push name: name.to_s, klass: klass, foreign_key: foreign_key.to_s, id_key: "id"
      end

      def computed_attribute(name, deps, &block)
        klass = Class.new(ComputedAttribute) do
          depends deps

          define_method(:value, &block)
        end
        attribute name, klass
      end

      def query_attribute(name, deps, &block)
        klass = Class.new(QueryAttribute) do
          depends deps

          define_method(:select_value, &block)
        end
        attribute name, klass
      end
    end

    def initialize(scope)
      @scope = scope
      @expose_attributes = []
      @datasource_data = {}
    end

    def select(*names)
      names = names.flat_map do |name|
        if name.kind_of?(Hash)
          # datasource data
          name.each_pair do |k, v|
            @datasource_data[k.to_s] = v
          end
          name.keys
        else
          name
        end
      end
      @expose_attributes = (@expose_attributes + names.map(&:to_s)).uniq
      self
    end

    def attribute_exposed?(name)
      @expose_attributes.include?(name)
    end

    def to_query
      to_query(@scope)
    end

    def results
      rows = get_rows(@scope)

      attribute_map = self.class._attributes.inject({}) do |hash, att|
        hash[att[:name]] = att
        hash
      end

      computed_expose_attributes = []
      datasources = {}

      @expose_attributes.each do |name|
        att = attribute_map[name]
        klass = att[:klass]
        next unless klass

        if klass.ancestors.include?(ComputedAttribute)
          computed_expose_attributes.push(att)
        elsif klass.ancestors.include?(Base)
          datasources[att] =
            included_datasource_rows(att, @datasource_data[att[:name]], rows)
        end
      end

      # TODO: field names...
      rows.each do |row|
        computed_expose_attributes.each do |att|
          klass = att[:klass]
          if klass
            row[att[:name]] = klass.new(row).value
          end
        end
        datasources.each_pair do |att, rows|
          row[att[:name]] = Array(rows[row[att[:id_key]]])
        end
        row.delete_if do |key, value|
          !attribute_exposed?(key)
        end
      end

      rows
    end
  end
end
