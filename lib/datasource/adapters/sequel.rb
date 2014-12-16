require 'set'

module Datasource
  module Adapters
    module Sequel
      module ScopeExtensions
        def use_datasource_serializer(value)
          @datasource_serializer = value
          self
        end

        def use_datasource(value)
          @datasource = value
          self
        end

        def get_datasource
          datasource = @datasource.new(self)
          datasource.select(*Array(@datasource_select))
          if @datasource_serializer
            select = []
            Datasource::Base.consumer_adapter.to_datasource_select(select, @datasource.orm_klass, @datasource_serializer, nil, datasource.adapter)

            datasource.select(*select)
          end
          datasource
        end

        def datasource_select(*args)
          @datasource_select = Array(@datasource_select) + args
          self
        end

        def each(&block)
          if @datasource
            datasource = get_datasource

            datasource.results.each(&block)
          else
            super
          end
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
                self.extend(ScopeExtensions).use_datasource(Adapters::Sequel.scope_to_class(self).default_datasource)
              end
              scope.use_datasource_serializer(serializer || Datasource::Base.consumer_adapter.get_serializer_for(Adapters::Sequel.scope_to_class(scope)))
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

        def for_serializer(serializer = nil)
          datasource_class = self.class.default_datasource
          pk = datasource_class.primary_key.to_sym

          scope = self.class
          .with_datasource(datasource_class)
          .for_serializer(serializer).where(pk => send(pk))

          datasource = scope.get_datasource
          if datasource.can_upgrade?(self)
            datasource.upgrade_records(self).first
          else
            scope.first
          end
        end

        module ClassMethods
          def default_datasource
            @default_datasource ||= Datasource::From(self)
          end

          def datasource_module(&block)
            default_datasource.instance_exec(&block)
          end
        end
      end

    module_function
      def association_reflection(klass, name)
        reflection = klass.association_reflections[name]

        macro = case reflection[:type]
        when :many_to_one then :belongs_to
        when :one_to_many then :has_many
        when :one_to_one then :has_one
        else
          fail Datasource::Error, "unimplemented association type #{reflection[:type]} - TODO"
        end
        {
          klass: reflection[:cache][:class] || reflection[:class_name].constantize,
          macro: macro,
          foreign_key: reflection[:key].try!(:to_s)
        }
      end

      def get_table_name(klass)
        klass.table_name
      end

      def is_scope?(obj)
        obj.kind_of?(::Sequel::Dataset)
      end

      def scope_to_class(scope)
        if scope.row_proc && scope.row_proc.ancestors.include?(::Sequel::Model)
          scope.row_proc
        else
          fail Datasource::Error, "unable to determine model for scope"
        end
      end

      def scope_loaded?(scope)
        false
      end

      def has_attribute?(record, name)
        record.values.key?(name.to_sym)
      end

      def get_assoc_eager_options(klass, name, assoc_select, append_select)
        if reflection = association_reflection(klass, name)
          self_append_select = []
          Datasource::Base.reflection_select(reflection, append_select, self_append_select)
          assoc_class = reflection[:klass]

          datasource_class = assoc_class.default_datasource

          {
            name => ->(ds) {
              ds.with_datasource(datasource_class)
              .datasource_select(*(self_append_select + assoc_select))
            }
          }
        else
          {}
        end
      end

      def get_sequel_select_values(values = nil)
        values.map { |str| ::Sequel.lit(str) }
      end

      def to_query(ds)
        ds.scope.sql
      end

      def select_scope(ds)
        ds.scope.select(*get_sequel_select_values(ds.get_select_values))
      end

      def upgrade_records(ds, records)
        get_final_scope(ds).send :post_load, records
        ds.results(records)
      end

      def get_final_scope(ds)
        eager = {}
        append_select = []
        ds.expose_associations.each_pair do |assoc_name, assoc_select|
          eager.merge!(
            get_assoc_eager_options(ds.class.orm_klass, assoc_name.to_sym, assoc_select, append_select))
        end
        # TODO: remove/disable datasource on scope if present
        scope = select_scope(ds)
        if scope.respond_to?(:use_datasource)
          scope = scope.clone.use_datasource(nil)
        end
        scope
        .select_append(*get_sequel_select_values(append_select.map { |v| primary_scope_table(ds) + ".#{v}" }))
        .eager(eager)
      end

      def get_rows(ds)
        get_final_scope(ds).all
      end

      def primary_scope_table(ds)
        ds.scope.first_source_alias.to_s
      end

      def ensure_table_join!(ds, name, att)
        join_value = Hash(ds.scope.opts[:join]).find do |value|
          (value.table_alias || value.table).to_s == att[:name]
        end
        fail Datasource::Error, "given scope does not join on #{name}, but it is required by #{att[:name]}" unless join_value
      end

      module DatasourceGenerator
        def From(klass)
          if klass.ancestors.include?(::Sequel::Model)
            Class.new(Datasource::Base) do
              attributes *klass.columns
              associations *klass.associations

              define_singleton_method(:orm_klass) do
                klass
              end

              define_singleton_method(:default_adapter) do
                Datasource::Adapters::Sequel
              end

              define_singleton_method(:primary_key) do
                klass.primary_key
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

if not(::Sequel::Model.respond_to?(:datasource_module))
  class ::Sequel::Model
    include Datasource::Adapters::Sequel::Model
  end
end
