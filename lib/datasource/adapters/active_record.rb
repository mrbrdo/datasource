require 'set'
require 'active_support/concern'

module Datasource
  module Adapters
    module ActiveRecord
      module ScopeExtensions
        def self.get_serializer_for(klass)
          "#{klass.name}Serializer".constantize
        end

        def self.association_klass(reflection)
          if reflection.macro == :belongs_to && reflection.options[:polymorphic]
            fail Datasource::Error, "polymorphic belongs_to not supported, write custom loader"
          else
            reflection.klass
          end
        end

        def self.preload_association(records, name)
          return if records.empty?
          return if records.first.association(name.to_sym).loaded?
          klass = records.first.class
          if reflection = klass.reflections[name.to_sym]
            assoc_class = ScopeExtensions.association_klass(reflection)
            datasource_class = assoc_class.default_datasource
            # TODO: extract serializer_class from parent serializer association
            serializer_class = ScopeExtensions.get_serializer_for(assoc_class)

            # TODO: can we make it use datasource scope (with_serializer)? like Sequel
            scope = assoc_class.all
            datasource = datasource_class.new(scope)
            datasource.select(*serializer_class._attributes)
            select_values = datasource.get_select_values

            begin
              ::ActiveRecord::Associations::Preloader
                .new.preload(records, name, assoc_class.select(*select_values))
            rescue ArgumentError
              ::ActiveRecord::Associations::Preloader
                .new(records, name, assoc_class.select(*select_values)).run
            end

            serializer_class._associations.each_pair do |assoc_name, options|
              assoc_records = records.flat_map { |record| record.send(name) }.compact
              preload_association(assoc_records, assoc_name)
            end
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

        def to_a
          datasource = @datasource.new(self)
          datasource.select(*@datasource_serializer._attributes)
          datasource.select_scope!
          records = datasource.results(super)
          @datasource_serializer._associations.each_pair do |name, options|
            ScopeExtensions.preload_association(records, name)
          end
          records
        end
      end

      module Model
        extend ActiveSupport::Concern

        included do
          attr_accessor :loaded_values
        end

        module ClassMethods
          def for_serializer(serializer = nil)
            scope = if all.respond_to?(:use_datasource_serializer)
              all
            else
              all.extending(ScopeExtensions).use_datasource(default_datasource)
            end
            scope.use_datasource_serializer(serializer || ScopeExtensions.get_serializer_for(scope.klass))
          end

          def with_datasource(datasource = nil)
            scope = if all.respond_to?(:use_datasource)
              all
            else
              all.extending(ScopeExtensions)
            end
            scope.use_datasource(datasource || default_datasource)
          end

          def default_datasource
            @default_datasource ||= Class.new(Datasource::From(self))
          end

          def datasource_module(&block)
            default_datasource.instance_exec(&block)
          end
        end
      end

      def self.get_table_name(klass)
        klass.table_name.to_sym
      end

      def self.is_scope?(obj)
        obj.kind_of?(ActiveRecord::Relation)
      end

      def self.scope_to_class(scope)
        scope.klass
      end

      def to_query
        ActiveRecord::Base.uncached do
          @scope.select(*get_select_values).to_sql
        end
      end

      def select_scope!
        @scope.select_values = get_select_values
      end

      def select_scope
        @scope.select(*get_select_values)
      end

      def get_rows
        select_scope.to_a
      end

      def get_select_values
        select_values = Set.new
        select_values.add("#{@scope.klass.table_name}.#{primary_key}")

        self.class._attributes.values.each do |att|
          if attribute_exposed?(att[:name])
            if att[:klass] == nil
              select_values.add("#{@scope.klass.table_name}.#{att[:name]}")
            elsif att[:klass].ancestors.include?(Attributes::ComputedAttribute)
              att[:klass]._depends.keys.map(&:to_s).each do |name|
                next if name == @scope.klass.table_name
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
                next if name == @scope.klass.table_name
                ensure_table_join!(@scope, name, att)
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
        fail Datasource::Error, "given scope does not join on #{name}, but it is required by #{att[:name]}" unless join_value
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

              define_singleton_method(:orm_klass) do
                klass
              end

              define_method(:primary_key) do
                klass.primary_key.to_sym
              end

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

ActiveSupport.on_load :active_record do
  if not(::ActiveRecord::Base.respond_to?(:datasource_module))
    class ::ActiveRecord::Base
      include Datasource::Adapters::ActiveRecord::Model
    end
  end
end
