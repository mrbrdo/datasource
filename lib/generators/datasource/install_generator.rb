class Datasource::InstallGenerator < ::Rails::Generators::Base
  source_root File.expand_path("../templates", __FILE__)
  desc 'Creates a Datasource Rails initializer'

  def create_serializer_file
    template 'initializer.rb', 'config/initializers/datasource.rb'
  end
end
