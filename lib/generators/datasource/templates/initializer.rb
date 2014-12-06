Datasource.load(:activerecord)

if defined? ActiveModel::Serializer
  if ActiveModel::Serializer.respond_to?(:config)
    ActiveModel::Serializer.config.array_serializer = Datasource::ArrayAMS
  else
    ActiveModel::Serializer.setup do |config|
      config.array_serializer = Datasource::ArrayAMS
    end
  end
end
