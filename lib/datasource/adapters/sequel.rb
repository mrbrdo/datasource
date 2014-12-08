require 'set'

module Datasource
  module Adapters
    module Sequel
      module ScopeExtensions
        def self.get_serializer_for(klass, serializer_assoc = nil)
          serializer = if serializer_assoc
            if serializer_assoc.kind_of?(Hash)
              serializer_assoc[:options].try(:[], :serializer)
            else
              serializer_assoc.options[:serializer]
            end
          end
          serializer || "#{klass.name}Serializer".constantize
        end

        def self.get_assoc_eager_options(klass, name, append_select, serializer_assoc)
          if reflection = klass.association_reflections[name]
            self_append_select = []
            # append foreign key for belongs_to (many_to_one) assoication
            if reflection[:type] == :many_to_one
              append_select.push(reflection[:key])
            elsif [:one_to_many, :one_to_one].include?(reflection[:type])
              self_append_select.push(reflection[:key])
            else
              fail Datasource::Error, "unsupported association type #{reflection[:type]} - TODO"
            end

            assoc_class = reflection[:cache][:class] || reflection[:class_name].constantize

            datasource_class = assoc_class.default_datasource
            # TODO: extract serializer_class from parent serializer association
            serializer_class = ScopeExtensions.get_serializer_for(assoc_class, serializer_assoc)

            scope = assoc_class.where
            opts = { name => proc { |ds| ds.with_datasource(datasource_class).for_serializer(serializer_class) } }

            assoc_opts = {}
            serializer_class._associations.each_pair do |assoc_name, assoc|
              assoc_opts.merge!(get_assoc_eager_options(assoc_class, assoc_name, self_append_select, assoc))
            end

            opts = {
              name => proc do |ds|
                ds.with_datasource(datasource_class)
                .for_serializer(serializer_class)
                .datasource_select(*self_append_select)
              end
            }
            unless assoc_opts.empty?
              opts[name] = { opts[name] => assoc_opts }
            end

            opts
          else
            {}
          end
        rescue Exception => ex
          if ex.is_a?(SystemStackError) || ex.is_a?(Datasource::RecursionError)
            fail Datasource::RecursionError, "recursive association (involving #{name})"
          else
            raise
          end
        end

        def use_datasource_serializer(value)
          @datasource_serializer = value
          self
        end

        def use_datasource(value)
          @datasource = value
          self
        end

        def datasource_select(*args)
          @datasource_select = Array(@datasource_select) + args
          self
        end

        def all
          datasource = @datasource.new(self)
          datasource.select(*(Array(@datasource_select) + @datasource_serializer._attributes))
          @opts[:eager] = {}
          append_select = []
          @datasource_serializer._associations.each do |name, assoc|
            @opts[:eager].merge!(
              ScopeExtensions
              .get_assoc_eager_options(@datasource.orm_klass, name, append_select, assoc))
          end
          datasource.select(*append_select) unless append_select.empty?
          @opts[:select] = datasource.get_sequel_select_values
          datasource.results(super)
        end
      end

      module Model
        extend ActiveSupport::Concern

        included do
          attr_accessor :loaded_values

          dataset_module do
            def for_serializer(serializer = nil)
              scope = if respond_to?(:use_datasource_serializer)
                self
              else
                self.extend(ScopeExtensions).use_datasource(default_datasource)
              end
              scope.use_datasource_serializer(serializer || ScopeExtensions.get_serializer_for(Adapters::Sequel.scope_to_class(scope)))
            end

            def with_datasource(datasource = nil)
              scope = if respond_to?(:use_datasource)
                self
              else
                self.extend(ScopeExtensions)
              end
              scope.use_datasource(datasource || default_datasource)
            end
          end
        end

        module ClassMethods
          def default_datasource
            @default_datasource ||= Class.new(Datasource::From(self))
          end

          def datasource_module(&block)
            default_datasource.instance_exec(&block)
          end
        end
      end

      def self.get_table_name(klass)
        klass.table_name
      end

      def self.is_scope?(obj)
        obj.kind_of?(::Sequel::Dataset)
      end

      def self.scope_to_class(scope)
        if scope.row_proc && scope.row_proc.ancestors.include?(::Sequel::Model)
          scope.row_proc
        else
          fail Datasource::Error, "unable to determine model for scope"
        end
      end

      def to_query(scope)
        scope.sql
      end

      def select_scope
        @scope.select(*get_sequel_select_values)
      end

      def get_rows
        select_scope.to_a.map(&:stringify_keys)
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

      def get_sequel_select_values
        get_select_values.map { |str| ::Sequel.lit(str) }
      end

      # not ORM-specific
      def get_select_values
        scope_table = primary_scope_table(@scope)
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
                ensure_table_join!(@scope, name, att)
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
                ensure_table_join!(@scope, name, att)
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
        fail Datasource::Error, "given scope does not join on #{name}, but it is required by #{att[:name]}" unless join_value
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

              define_singleton_method(:orm_klass) do
                klass
              end

              define_method(:primary_key) do
                klass.primary_key
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

# TODO:
#ActiveSupport.on_load(:sequel) do
  if not(::Sequel::Model.respond_to?(:datasource_module))
    class ::Sequel::Model
      include Datasource::Adapters::Sequel::Model
    end
  end
#end
