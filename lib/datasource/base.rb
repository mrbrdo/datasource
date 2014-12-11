module Datasource
  class Base
    class << self
      attr_accessor :_attributes, :_associations, :_update_scope, :_loaders
      attr_writer :orm_klass

      def inherited(base)
        base._attributes = (_attributes || {}).dup
        base._associations = (_associations || {}).dup
        base._loaders = (_loaders || {}).dup
      end

      def default_adapter
        @adapter ||= begin
          Datasource::Adapters.const_get(Datasource::Adapters.constants.first)
        end
      end

      def consumer_adapter
        @consumer_adapter = Datasource::ConsumerAdapters::ActiveModelSerializers
      end

      def orm_klass
        fail Datasource::Error, "Model class not set for #{name}. You should define it:\nclass YourDatasource\n  @orm_klass = MyModelClass\nend"
      end

      def reflection_select(reflection, parent_select, assoc_select)
        # append foreign key depending on assoication
        if reflection[:macro] == :belongs_to
          parent_select.push(reflection[:foreign_key])
        elsif [:has_many, :has_one].include?(reflection[:macro])
          assoc_select.push(reflection[:foreign_key])
        else
          fail Datasource::Error, "unsupported association type #{reflection[:macro]} - TODO"
        end
      end

    private
      def attributes(*attrs)
        attrs.each { |name| attribute(name) }
      end

      def associations(*assocs)
        assocs.each { |name| association(name) }
      end

      def association(name)
        @_associations[name.to_s] = true
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

    attr_reader :scope, :expose_attributes, :expose_associations, :adapter

    def initialize(scope, adapter = nil)
      @adapter = adapter || self.class.default_adapter
      @scope =
        if self.class._update_scope
          self.class._update_scope.call(scope)
        else
          scope
        end
      @expose_attributes = []
      @expose_associations = {}
    end

    def primary_key
      :id
    end

    def select_all
      @expose_attributes = self.class._attributes.keys.dup
    end

    def select(*names)
      failure = ->(name) { fail Datasource::Error, "attribute or association #{name} doesn't exist for #{self.class.orm_klass.name}, did you forget to call \"computed :#{name}, <dependencies>\" in your datasource_module?" }
      names.each do |name|
        if name.kind_of?(Hash)
          name.each_pair do |assoc_name, assoc_select|
            assoc_name = assoc_name.to_s
            if self.class._associations.key?(assoc_name)
              @expose_associations[assoc_name] ||= []
              @expose_associations[assoc_name] += Array(assoc_select)
              @expose_associations[assoc_name].uniq!
            else
              failure.call(assoc_name)
            end
          end
        else
          name = name.to_s
          if self.class._attributes.key?(name)
            @expose_attributes.push(name)
          else
            failure.call(name)
          end
        end
      end
      @expose_attributes.uniq!
      self
    end

    def get_select_values
      scope_table = adapter.primary_scope_table(self)
      select_values = Set.new
      select_values.add("#{scope_table}.#{primary_key}")

      self.class._attributes.values.each do |att|
        if attribute_exposed?(att[:name])
          if att[:klass] == nil
            select_values.add("#{scope_table}.#{att[:name]}")
          elsif att[:klass].ancestors.include?(Attributes::ComputedAttribute)
            att[:klass]._depends.keys.map(&:to_s).each do |name|
              next if name == scope_table
              next if name == "loaders"
              adapter.ensure_table_join!(self, name, att)
            end
            att[:klass]._depends.each_pair do |table, names|
              next if table.to_sym == :loaders
              Array(names).each do |name|
                select_values.add("#{table}.#{name}")
              end
              # TODO: handle depends on virtual attribute
            end
          elsif att[:klass].ancestors.include?(Attributes::QueryAttribute)
            select_values.add("(#{att[:klass].select_value}) as #{att[:name]}")
            att[:klass]._depends.each do |name|
              next if name == scope_table
              adapter.ensure_table_join!(self, name, att)
            end
          end
        end
      end
      select_values.to_a
    end

    def attribute_exposed?(name)
      @expose_attributes.include?(name.to_s)
    end

    def results(rows = nil)
      rows ||= adapter.get_rows(self)

      @expose_attributes.each do |name|
        att = self.class._attributes[name]
        fail Datasource::Error, "attribute #{name} doesn't exist for #{self.class.orm_klass.name}, did you forget to call \"computed :#{name}, <dependencies>\" in your datasource_module?" unless att
        klass = att[:klass]
        next unless klass

        next if rows.empty?

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
