module Datasource
  class Serializer
    TemplatePart = Struct.new(:parent, :type, :value, :select) do
      def initialize(parent, type = nil, value = nil)
        super(parent, type, get_default_value(type, value), [])
      end

      def set_default_value(value = nil)
        self.value = get_default_value(type, value)
      end
    private
      def get_default_value(type, value)
        case type
        when :hash then {}
        when :array then []
        when :datasource then value
        when nil then nil
        else
          fail "Unknown type #{type}"
        end
      end
    end

    class << self
      attr_accessor :datasource_count, :template

      def inherited(base)
        base.datasource_count = 0
        @cursor = base.template = nil
      end

      def with_new_cursor(type, value = nil, &block)
        result = nil
        new_cursor = TemplatePart.new(@cursor, type, value)
        @cursor = @cursor.tap do
          if template.nil?
            self.template = @cursor = new_cursor
          elsif @cursor.type == :datasource
            @cursor = @cursor.parent
            return with_new_cursor(type, value, &block)
          elsif @cursor.type == :array
            @cursor = new_cursor
            @cursor.parent.push(@cursor)
          elsif @cursor.type.nil?
            # replace cursor
            @cursor.type = type
            @cursor.set_default_value(value)
          else
            fail "Invalid use of #{type}."
          end
          result = block.call
        end
        result
      end

      def hash(&block)
        with_new_cursor(:hash, &block)
      end

      def key(name)
        fail "Cannot use key outside hash." unless template && @cursor.type == :hash
        @cursor = @cursor.tap do
          @cursor = @cursor.value[name.to_s] = TemplatePart.new(@cursor)
          yield
        end
      end

      def array(&block)
        with_new_cursor(:array, &block)
      end

      def datasource(ds)
        self.datasource_count += 1
        @cursor = with_new_cursor(:datasource, ds) { @cursor }
      end

      def attributes(*attributes)
        attributes.each { |name| attribute name }
      end

      def attribute(name)
        fail "No datasource selected - use \"select_datasource Klass\" first." unless template && @cursor.type == :datasource
        @cursor.select << name
      end
    end

    def initialize(*scopes)
      @scopes = scopes
      if @scopes.size != self.class.datasource_count
        fail ArgumentError, "#{self.class.name} needs #{self.class.datasource_count} scopes, you provided #{@scopes.size}"
      end
    end

    def as_json
      parse_template_part(self.class.template)
    end

  private
    def parse_template_part(part)
      return nil unless part
      case part.type
      when :hash
        {}.tap do |result|
          part.value.each_pair do |k, v|
            result[k] = parse_template_part(v)
          end
        end
      when :array
        part.value.map { |v| parse_template_part(v) }
      when :datasource
        part.value.new(@scopes.shift).select(*part.select).results
      else
        fail "Unknown type #{type}"
      end
    end
  end
end
