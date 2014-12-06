module Datasource
  class Base
    class << self
      attr_accessor :_attributes, :_update_scope, :_loaders
      attr_accessor :adapter

      def inherited(base)
        base._attributes = (_attributes || []).dup
        base._loaders = (_loaders || {}).dup
        @adapter ||= if defined? ActiveRecord
          Datasource::Adapters::ActiveRecord
        elsif defined? Sequel
          Datasource::Adapters::Sequel
        end
        self.send :include, @adapter
      end

    private
      def attributes(*attrs)
        attrs.each { |name| attribute(name) }
      end

      def attribute(name, klass = nil)
        @_attributes.push name: name.to_s, klass: klass
      end

      def includes_many(name, klass, foreign_key)
        @_attributes.push name: name.to_s, klass: klass, foreign_key: foreign_key.to_s, id_key: self::ID_KEY
      end

      def update_scope(&block)
        @_update_scope = block
      end

      def loader(name, &block)
        @_loaders[name.to_sym] = block
      end

      def group_by_column(column, rows, remove_column = false)
        rows.inject({}) do |map, row|
          map[row[column]] = row
          row.delete(column) if remove_column
          map
        end
      end
    end

    def initialize(scope)
      @scope =
        if self.class._update_scope
          self.class._update_scope.call(scope)
        else
          scope
        end
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

        if klass.ancestors.include?(Attributes::ComputedAttribute)
          computed_expose_attributes.push(att)
        elsif klass.ancestors.include?(Base)
          datasources[att] =
            included_datasource_rows(att, @datasource_data[att[:name]], rows)
        end
      end

      loader_results = {}

      # TODO: field names...
      rows.each do |row|
        # lazy load orm model only if used in computed attributes
        orm_model = nil
        get_orm_model = -> { orm_model ||= to_orm_object(row) }

        row_computed = {}
        computed_expose_attributes.each do |att|
          klass = att[:klass]
          if klass
            row_computed[att[:name]] = if klass._depends.keys.include?(:loader)
              row_loader_results ||= Array(klass._depends[:loader]).map do |loader_name|
                (loader_results[loader_name] ||= self.class._loaders[loader_name].call(rows, @scope))[row[self.class::ID_KEY]]
              end
              klass.new(row, get_orm_model).value(*row_loader_results)
            else
              klass.new(row, get_orm_model).value
            end
          end
        end
        row.merge!(row_computed)

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
