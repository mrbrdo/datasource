require 'set'
require 'active_support/concern'

module Datasource
  module Adapters
    module ActiveRecord
      module ScopeExtensions
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

      private
        def exec_queries
          if @datasource
            datasource = @datasource.new(self)
            datasource.select(*Array(@datasource_select))
            if @datasource_serializer
              select = []
              Datasource::Base.consumer_adapter.to_datasource_select(select, @datasource.orm_klass, @datasource_serializer)

              datasource.select(*select)
            end

            @loaded = true
            @records = datasource.results
          else
            super
          end
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
            scope.use_datasource_serializer(serializer || Datasource::Base.consumer_adapter.get_serializer_for(Adapters::ActiveRecord.scope_to_class(scope)))
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

      def self.association_reflection(klass, name)
        if reflection = klass.reflections[name]
          {
            klass: reflection.klass,
            macro: reflection.macro,
            foreign_key: reflection.try(:foreign_key)
          }
        end
      end

      def self.get_table_name(klass)
        klass.table_name.to_sym
      end

      def self.is_scope?(obj)
        obj.kind_of?(::ActiveRecord::Relation)
      end

      def self.scope_to_class(scope)
        scope.klass
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
          assoc_class = association_klass(reflection)
          datasource_class = assoc_class.default_datasource
          # TODO: extract serializer_class from parent serializer association
          serializer_class = Datasource::Base.consumer_adapter.get_serializer_for(assoc_class)

          # TODO: can we make it use datasource scope (with_serializer)? like Sequel
          scope = assoc_class.all
          datasource = datasource_class.new(scope)
          datasource_select = serializer_class._attributes.dup
          Datasource::Base.reflection_select(Adapters::ActiveRecord.association_reflection(klass, name.to_sym), [], datasource_select)
          datasource.select(*datasource_select)
          select_values = datasource.get_select_values

          begin
            ::ActiveRecord::Associations::Preloader
              .new.preload(records, name, assoc_class.select(*select_values))
          rescue ArgumentError
            ::ActiveRecord::Associations::Preloader
              .new(records, name, assoc_class.select(*select_values)).run
          end

          assoc_records = records.flat_map { |record| record.send(name) }.compact
          serializer_class._associations.each_pair do |assoc_name, options|
            preload_association(assoc_records, assoc_name)
          end
          datasource.results(assoc_records)
        end
      rescue Exception => ex
        if ex.is_a?(SystemStackError) || ex.is_a?(Datasource::RecursionError)
          fail Datasource::RecursionError, "recursive association (involving #{name})"
        else
          raise
        end
      end

      def to_query
        ::ActiveRecord::Base.uncached do
          @scope.select(*get_select_values).to_sql
        end
      end

      def select_scope
        @scope.select(*get_select_values)
      end

      def get_rows
        append_select = []
        @expose_associations.each_pair do |assoc_name, assoc_select|
          if reflection = Adapters::ActiveRecord.association_reflection(self.class.orm_klass, assoc_name.to_sym)
            Datasource::Base.reflection_select(reflection, append_select, [])
          end
        end
        select(*append_select)

        scope = select_scope
        if scope.respond_to?(:use_datasource)
          scope = scope.spawn.use_datasource(nil)
        end
        scope.includes_values = []
        scope.to_a.tap do |records|
          @expose_associations.each_pair do |assoc_name, assoc_select|
            Adapters::ActiveRecord.preload_association(records, assoc_name)
          end
        end
      end

      def primary_scope_table(scope)
        scope.klass.table_name
      end

      def ensure_table_join!(name, att)
        join_value = @scope.joins_values.find do |value|
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
        def From(klass)
          if klass.ancestors.include?(::ActiveRecord::Base)
            Class.new(Datasource::Base) do
              attributes *klass.column_names
              associations *klass.reflections.keys

              define_singleton_method(:orm_klass) do
                klass
              end

              define_method(:primary_key) do
                klass.primary_key.to_sym
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

if not(::ActiveRecord::Base.respond_to?(:datasource_module))
  class ::ActiveRecord::Base
    include Datasource::Adapters::ActiveRecord::Model
  end
end
