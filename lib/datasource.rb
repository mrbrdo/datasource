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
  end

  def select(*names)
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

    computed_expose_attributes = @expose_attributes.select do |v|
      attribute_map[v][:klass] &&
        attribute_map[v][:klass].ancestors.include?(ComputedAttribute)
    end

    # TODO: field names...
    rows.each do |row|
      computed_expose_attributes.each do |key|
        klass = attribute_map[key][:klass]
        if klass
          row[key] = klass.new(row).value
        end
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
