module Datasource
  class Base
    class << self
      attr_accessor :_attributes, :_update_scope, :_loaders
      attr_writer :orm_klass

      def inherited(base)
        base._attributes = (_attributes || {}).dup
        base._loaders = (_loaders || {}).dup
        self.send :include, adapter
      end

      def adapter
        @adapter ||= if defined? ActiveRecord
          Datasource::Adapters::ActiveRecord
        elsif defined? Sequel
          Datasource::Adapters::Sequel
        end
      end

      def orm_klass
        fail Datasource::Error, "Model class not set for #{name}. You should define it:\nclass YourDatasource\n  @orm_klass = MyModelClass\nend"
      end

    private
      def attributes(*attrs)
        attrs.each { |name| attribute(name) }
      end

      def attribute(name, klass = nil)
        att = { name: name.to_s, klass: klass }
        @_attributes[att[:name]] = att
      end

      def update_scope(&block)
        # TODO: careful about scope module extension, to_a infinite recursion
        @_update_scope = block
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
    end

    def primary_key
      :id
    end

    def select(*names)
      @expose_attributes = (@expose_attributes + names.map(&:to_s)).uniq
      self
    end

    def attribute_exposed?(name)
      @expose_attributes.include?(name.to_s)
    end

    def results(rows = nil)
      rows ||= get_rows

      @expose_attributes.each do |name|
        att = self.class._attributes[name]
        fail Datasource::Error, "attribute #{name} doesn't exist for #{self.class.orm_klass.name}, did you forget to call \"computed :#{name}, <dependencies>\" in your datasource_module?" unless att
        klass = att[:klass]
        next unless klass

        if att[:klass].ancestors.include?(Attributes::ComputedAttribute)
          loaders = att[:klass]._depends[:loaders]
          if loaders
            Array(loaders).each do |name|
              if loader = self.class._loaders[name]
                if loaded_values = loader.load(rows.map(&primary_key), rows, @scope)
                  unless rows.first.loaded_values
                    rows.each do |row|
                      row.loaded_values = {}
                    end
                  end
                  rows.each do |row|
                    row.loaded_values[name] = loaded_values[row.send(primary_key)]
                  end
                end
              else
                raise Datasource::Error, "loader with name :#{name} could not be found"
              end
            end
          end
        end
      end

      rows
    end
  end
end
