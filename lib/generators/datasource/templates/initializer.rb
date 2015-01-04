Datasource.setup do |config|
  # Adapters to load
  # Available ORM adapters: activerecord, sequel
  # Available Serializer adapters: active_model_serializers
  config.adapters = [:activerecord, :active_model_serializers]
end
