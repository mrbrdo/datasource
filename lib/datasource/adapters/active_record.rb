require 'set'

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

module Datasource
  module Adapters
    module ActiveRecord
      ID_KEY = "id"

      def to_query(scope)
        ActiveRecord::Base.uncached do
          scope.select(*get_select_values(scope)).to_sql
        end
      end

      def get_rows(scope)
        scope.pluck_hash(*get_select_values(scope))
      end

      def included_datasource_rows(att, datasource_data, rows)
        ds_select = datasource_data[:select]
        unless ds_select.include?(att[:foreign_key])
          ds_select += [att[:foreign_key]]
        end
        ds_scope = datasource_data[:scope]
        column = "#{ds_scope.klass.table_name}.#{att[:foreign_key]}"
        ds_scope = ds_scope.where("#{column} IN (?)",
            rows.map { |row| row[att[:id_key]] })
        grouped_results = att[:klass].new(ds_scope)
        .select(ds_select)
        .results.group_by do |row|
          row[att[:foreign_key]]
        end
        unless datasource_data[:select].include?(att[:foreign_key])
          grouped_results.each_pair do |k, rows|
            rows.each do |row|
              row.delete(att[:foreign_key])
            end
          end
        end
        grouped_results
      end

      def get_select_values(scope)
        select_values = Set.new
        select_values.add("#{scope.klass.table_name}.#{self.class.adapter::ID_KEY}")

        self.class._attributes.each do |att|
          if attribute_exposed?(att[:name])
            if att[:klass] == nil
              select_values.add("#{scope.klass.table_name}.#{att[:name]}")
            elsif att[:klass].ancestors.include?(Attributes::ComputedAttribute)
              att[:klass]._depends.keys.map(&:to_s).each do |name|
                next if name == scope.klass.table_name
                ensure_table_join!(scope, name, att)
              end
              att[:klass]._depends.each_pair do |table, names|
                Array(names).each do |name|
                  select_values.add("#{table}.#{name}")
                end
                # TODO: handle depends on virtual attribute
              end
            elsif att[:klass].ancestors.include?(Attributes::QueryAttribute)
              select_values.add("(#{att[:klass].new.select_value}) as #{att[:name]}")
              att[:klass]._depends.each do |name|
                next if name == scope.klass.table_name
                ensure_table_join!(scope, name, att)
              end
            end
          end
        end
        select_values.to_a
      end

      def ensure_table_join!(scope, name, att)
        join_value = scope.joins_values.find do |value|
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

      module DatasourceGenerator
        def From(*args)
          klass = args.first
          if klass.ancestors.include?(::ActiveRecord::Base)
            assocs = args[1] || false
            skip = (args[2] || []).map(&:to_s)
            column_names = klass.column_names.reject do |name|
              skip.include?(name)
            end
            Class.new(Datasource::Base) do
              attributes *column_names

              if assocs
                klass.reflections.values.each do |reflection|
                  next if skip.include?(reflection.name.to_s)
                  if reflection.macro == :has_many
                    ds_name = "#{reflection.klass.name.pluralize}Datasource"
                    begin
                      ds_name.constantize
                    rescue NameError
                      begin
                        Object.const_set(ds_name, Datasource.From(reflection.klass))
                      rescue SystemStackError
                        fail "Circular reference between #{klass.name} and #{reflection.klass.name}, create Datasets manually"
                      end
                    end
                    includes_many reflection.name, ds_name.constantize, reflection.foreign_key
                  end
                end
              end
            end
          else
            super if defined?(super)
          end
        end
      end
    end
  end

  extend Adapters::ActiveRecord::DatasourceGenerator
end
