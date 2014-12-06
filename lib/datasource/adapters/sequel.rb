require 'set'

module Datasource
  module Adapters
    module Sequel
      ID_KEY = "id"

      def to_query(scope)
        scope.sql
      end

      def orm_klass
        raise "Model class not set for #{self.name}. You should define it:\ndef orm_klass\n  Post\nend"
      end

      def to_orm_object(row)
        orm_klass.new(row.select { |k,v| orm_klass.columns.include?(k.to_sym) && k != "id" })
      end

      def get_rows(scope)
        # directly return hash from database instead of Sequel model
        scope.row_proc = ->(x) { x }
        scope.select(*get_sequel_select_values(scope)).to_a.map(&:stringify_keys)
      end

      # not ORM-specific
      def included_datasource_rows(att, datasource_data, rows)
        ds_select = datasource_data[:select]
        unless ds_select.include?(att[:foreign_key])
          ds_select += [att[:foreign_key]]
        end
        ds_scope = datasource_data[:scope]
        column = "#{primary_scope_table(ds_scope)}.#{att[:foreign_key]}"
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

      def get_sequel_select_values(scope)
        get_select_values(scope).map { |str| ::Sequel.lit(str) }
      end

      # not ORM-specific
      def get_select_values(scope)
        scope_table = primary_scope_table(scope)
        select_values = Set.new
        select_values.add("#{scope_table}.#{self.class.adapter::ID_KEY}")

        self.class._attributes.each do |att|
          if attribute_exposed?(att[:name])
            if att[:klass] == nil
              select_values.add("#{scope_table}.#{att[:name]}")
            elsif att[:klass].ancestors.include?(Attributes::ComputedAttribute)
              att[:klass]._depends.keys.map(&:to_s).each do |name|
                next if name == scope_table
                next if name == "loader"
                ensure_table_join!(scope, name, att)
              end
              att[:klass]._depends.each_pair do |table, names|
                next if table.to_sym == :loader
                Array(names).each do |name|
                  select_values.add("#{table}.#{name}")
                end
                # TODO: handle depends on virtual attribute
              end
            elsif att[:klass].ancestors.include?(Attributes::QueryAttribute)
              select_values.add("(#{att[:klass].new.select_value}) as #{att[:name]}")
              att[:klass]._depends.each do |name|
                next if name == scope_table
                ensure_table_join!(scope, name, att)
              end
            end
          end
        end
        select_values.to_a
      end

      def primary_scope_table(scope)
        scope.first_source_alias.to_s
      end

      def ensure_table_join!(scope, name, att)
        join_value = Hash(scope.opts[:join]).find do |value|
          (value.table_alias || value.table).to_s == att[:name]
        end
        raise "Given scope does not join on #{name}, but it is required by #{att[:name]}" unless join_value
      end

      module DatasourceGenerator
        def From(*args)
          klass = args.first
          if klass.ancestors.include?(::Sequel::Model)
            assocs = args[1] || false
            skip = (args[2] || []).map(&:to_s)
            column_names = klass.columns.reject do |name|
              skip.include?(name.to_s)
            end
            Class.new(Datasource::Base) do
              attributes *column_names

              define_method(:orm_klass) do
                klass
              end

              if assocs
                klass.associations.each do |association|
                  reflection = klass.association_reflection(association)
                  next if skip.include?(reflection[:name].to_s)
                  if reflection[:type] == :many_to_many
                    ds_name = "#{reflection[:model].name.pluralize}Datasource"
                    begin
                      ds_name.constantize
                    rescue NameError
                      begin
                        Object.const_set(ds_name, Datasource.From(reflection[:model]))
                      rescue SystemStackError
                        fail "Circular reference between #{klass.name} and #{reflection[:model].name}, create Datasets manually"
                      end
                    end
                    includes_many reflection[:name], ds_name.constantize, reflection[:key]
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

  extend Adapters::Sequel::DatasourceGenerator
end
