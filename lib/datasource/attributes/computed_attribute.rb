module Datasource
  module Attributes
    class ComputedAttribute
      class << self
        attr_accessor :_depends

        def inherited(base)
          base._depends = (_depends || {}).dup # TODO: deep dup?
        end

        def depends(*args)
          args.each do |dep|
            _depends.deep_merge!(dep)
          end
        end
      end
    end
  end

  class Datasource::Base
  private
    def self.computed(name, *_deps)
      deps = _deps.select { |dep| dep.kind_of?(Hash) }
      _deps.reject! { |dep| dep.kind_of?(Hash) }
      unless _deps.empty?
        self_key = default_adapter.get_table_name(orm_klass)
        deps.push(self_key => _deps)
      end

      klass = Class.new(Attributes::ComputedAttribute) do
        depends *deps
      end

      attribute name, klass
    end
  end
end
