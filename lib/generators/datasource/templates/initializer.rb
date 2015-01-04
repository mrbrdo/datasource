Datasource.setup do |config|
  # Adapters to load
  # Available ORM adapters: activerecord, sequel
  # Available Serializer adapters: active_model_serializers
  config.adapters = [:activerecord, :active_model_serializers]

  # Enable simple mode, which will always select all model database columns,
  # making Datasource easier to use. See documentation for details.
  config.simple_mode = true
end
