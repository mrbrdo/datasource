ActiveRecord::Calculations
module ActiveRecord
  module Calculations
    def pluck_hash(*column_names)
      column_names.map! do |column_name|
        if column_name.is_a?(Symbol) && attribute_alias?(column_name)
          attribute_alias(column_name)
        else
          column_name.to_s
        end
      end

      if has_include?(column_names.first)
        construct_relation_for_association_calculations.pluck(*column_names)
      else
        relation = spawn
        relation.select_values = column_names.map { |cn|
          columns_hash.key?(cn) ? arel_table[cn] : cn
        }
        result = klass.connection.select_all(relation.arel, nil, bind_values)
        columns = result.columns.map do |key|
          klass.column_types.fetch(key) {
            result.column_types.fetch(key) { result.identity_type }
          }
        end

        result.rows.map do |values|
          {}.tap do |hash|
            values.zip(columns, result.columns).each do |v|
              single_attr_hash = { v[2] => v[0] }
              hash[v[2]] = v[1].type_cast klass.initialize_attributes(single_attr_hash).values.first
            end
          end
        end
      end
    end
  end
end

class Datasource
  class << self
    attr_accessor :_attributes, :_virtual_attributes, :_associations

    def inherited(base)
      base._attributes = (_attributes || []).dup
    end

    def attributes(*attrs)
      attrs.each { |name| attribute(name) }
    end

    def attribute(name, klass = nil)
      @_attributes.push name: name.to_s, klass: klass
    end

    def includes_many(name, klass, foreign_key)
      @_attributes.push name: name.to_s, klass: klass, foreign_key: foreign_key.to_s
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

  def initialize(scope)
    @scope = scope
    @expose_attributes = []
    @select_attributes = []
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
    append_required_select_values
    self
  end

  def to_sql
    @scope.select(*select_values).to_sql
  end

  def results
    rows = @scope.pluck_hash(*select_values)

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
      elsif klass.ancestors.include?(Datasource)
        ds_select = @datasource_data[att[:name]][:select]
        unless ds_select.include?(att[:foreign_key])
          ds_select += [att[:foreign_key]]
        end
        ds_scope = @datasource_data[att[:name]][:scope]
        column = "#{ds_scope.klass.table_name}.#{att[:foreign_key]}"
        ds_scope = ds_scope.where("#{column} IN (?)",
            rows.map { |row| row["id"] })
        datasources[att] = att[:klass].new(ds_scope)
        .select(ds_select)
        .results.group_by do |row|
          row[att[:foreign_key]]
        end
        unless @datasource_data[att[:name]][:select].include?(att[:foreign_key])
          datasources[att].each_pair do |k, rows|
            rows.each do |row|
              row.delete(att[:foreign_key])
            end
          end
        end
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
        row[att[:name]] = Array(rows[row["id"]])
      end
      row.delete_if do |key, value|
        !@expose_attributes.include?(key)
      end
    end

    rows
  end

private
  def select_values
    @select_attributes
  end

  def append_select_value(name)
    @select_attributes.push(name) unless @select_attributes.include?(name)
  end

  def append_required_select_values
    append_select_value("#{@scope.klass.table_name}.id")

    self.class._attributes.each do |att|
      if @expose_attributes.include?(att[:name])
        if att[:klass] == nil
          append_select_value("#{@scope.klass.table_name}.#{att[:name]}")
        elsif att[:klass].ancestors.include?(ComputedAttribute)
          att[:klass]._depends.keys.map(&:to_s).each do |name|
            next if name == @scope.klass.table_name
            check_table_join!(name, att)
          end
          att[:klass]._depends.each_pair do |table, names|
            Array(names).each do |name|
              append_select_value("#{table}.#{name}")
            end
            # TODO: handle depends on virtual attribute
          end
        elsif att[:klass].ancestors.include?(QueryAttribute)
          append_select_value("(#{att[:klass].new.select_value}) as #{att[:name]}")
          att[:klass]._depends.each do |name|
            next if name == @scope.klass.table_name
            check_table_join!(name, att)
          end
        end
      end
    end
  end

  def check_table_join!(name, att)
    join_value = @scope.joins_values.find do |value|
      if value.is_a?(Symbol)
        value.to_s == att[:name]
      elsif value.is_a?(String)
        if value =~ /join (\w+)/i
          $1 == att[:name]
        end
      end
    end
    raise "Given scope does not join on #{name}, but it is required by #{att[:name]}" unless join_value
  end
end
