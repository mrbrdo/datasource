require 'spec_helper'

module SimpleModeSpec
  describe "Simple Mode", :activerecord, :simple_mode do
    class Post < ActiveRecord::Base
      belongs_to :blog

      datasource_module do
        query :author_name do
          "posts.author_first_name || ' ' || posts.author_last_name"
        end
      end
    end

    class Blog < ActiveRecord::Base
      has_many :posts
    end

    class BlogSerializer < ActiveModel::Serializer
      attributes :id, :title

      has_many :posts
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title, :author_name
    end

    it "returns serialized hash" do
      blog = Blog.create! title: "Blog 1"
      blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
      blog.posts.create! title: "Post 2", author_first_name: "Maria", author_last_name: "Doe"
      blog = Blog.create! title: "Blog 2"

      expected_result = [
        {:id =>1, :title =>"Blog 1", :posts =>[
          {:id =>1, :title =>"Post 1", :author_name =>"John Doe"},
          {:id =>2, :title =>"Post 2", :author_name =>"Maria Doe"}
        ]},
        {:id =>2, :title =>"Blog 2", :posts =>[]}
      ]

      expect_query_count(2) do |logger|
        serializer = ActiveModel::ArraySerializer.new(Blog.all)
        expect(expected_result).to eq(serializer.as_json)
        expect(logger.string.lines[0]).to include("blogs.*")
        expect(logger.string.lines[1]).to include("posts.*")
        expect(logger.string.lines[1]).to_not include("posts.title")
      end
    end
  end
end
