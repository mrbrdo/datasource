require 'spec_helper'

module LoaderSpec
  describe "Loader" do
    class Comment < ActiveRecord::Base
      self.table_name = "comments"
      belongs_to :post
    end

    class Post < ActiveRecord::Base
      self.table_name = "posts"
      has_many :comments

      datasource_module do
        loader :newest_comment, group_by: :post_id, one: true do |post_ids|
          Comment.for_serializer.where(post_id: post_ids)
            .group("post_id")
            .having("id = MAX(id)")
            .datasource_select(:post_id)
        end

        loader :newest_comment_text, array_to_hash: true do |post_ids|
          Comment.where(post_id: post_ids)
            .group("post_id")
            .having("id = MAX(id)")
            .pluck("post_id, comment")
        end

        loader :ordered_comments, group_by: :post_id do |post_ids|
          Comment.for_serializer(CommentSerializer).where(post_id: post_ids)
            .order("post_id, id desc")
            .datasource_select(:post_id)
        end

        computed :newest_comment, loaders: :newest_comment
        computed :newest_comment_text, loaders: :newest_comment_text
        computed :ordered_comments, loaders: :ordered_comments
      end

      def name_initials
        return unless author_first_name && author_last_name
        author_first_name[0].upcase + author_last_name[0].upcase
      end
    end

    class CommentSerializer < ActiveModel::Serializer
      attributes :id, :comment
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title, :newest_comment, :newest_comment_text, :ordered_comments

      def newest_comment
        CommentSerializer.new(object.loaded_values[:newest_comment]).as_json
      end

      def newest_comment_text
        object.loaded_values[:newest_comment_text]
      end

      def ordered_comments
        ActiveModel::ArraySerializer.new(object.loaded_values[:ordered_comments]).as_json
      end
    end

    it "uses loader method" do
      post = Post.create! title: "First Post"
      2.times { |i| post.comments.create! comment: "Comment #{i+1}" }

      expect_query_count(4) do
        expect(ActiveModel::ArraySerializer.new(Post.all).as_json).to eq(
          [{:id=>1, :title=>"First Post", :newest_comment=>{"comment"=>{:id=>2, :comment=>"Comment 2"}}, :newest_comment_text=>"Comment 2", :ordered_comments=>[{:id=>2, :comment=>"Comment 2"}, {:id=>1, :comment=>"Comment 1"}]}]
        )
      end
    end
  end
end
