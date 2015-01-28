# Datasource

- Automatically preload associations for your serializers
- Specify custom SQL snippets for virtual attributes (Query attributes)
- Write custom preloading logic in a reusable way

** Note: the API of this gem is still unstable and may change a lot between versions! This project uses semantic versioning (until version 1.0.0, minor version changes may include API changes, but patch version will not) **

#### Install

Requires Ruby 2.0 or higher.

Add to Gemfile (recommended to use github version until API is stable)

```
gem 'datasource', github: 'mrbrdo/datasource'
```

```
bundle install
rails g datasource:install
```

#### Upgrade

```
rails g datasource:install
```

#### ORM support

- ActiveRecord
- Sequel

#### Serializer support

- active_model_serializers

### Associations

The most noticable magic effect of using Datasource is that associations will
automatically be preloaded using a single query.

```ruby
class PostSerializer < ActiveModel::Serializer
  attributes :id, :title
end

class UserSerializer < ActiveModel::Serializer
  attributes :id
  has_many :posts
end
```
```sql
SELECT users.* FROM users
SELECT posts.* FROM posts WHERE id IN (?)
```

This means you **do not** need to call `includes` yourself. It will be done
automatically by Datasource.

### Show action

If you use the more advanced features like Loaded, you will probably want to
reuse the same loading logic in your show action.
You will need to call `for_serializer` on the scope before you call `find`.
You can optionally give it the serializer class as an argument.

```ruby
class PostsController < ApplicationController
  def show
    post = Post.for_serializer.find(params[:id])
    # more explicit:
    # post = Post.for_serializer(PostSerializer).find(params[:id])

    render json: post
  end
end
```

You can also use it on an existing record, but doing it this way may result in
an additional SQL query (for example if you use query attributes).

```ruby
class UsersController < ApplicationController
  def show
    user = current_user.for_serializer

    render json: user
  end
end
```

### Query attribute

You can specify a SQL fragment for `SELECT` and use that as an attribute on your
model. As a simple example you can concatenate 2 strings together in SQL:

```ruby
class User < ActiveRecord::Base
  datasource_module do
    query :full_name do
      "users.first_name || ' ' || users.last_name"
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :full_name
end
```

```sql
SELECT users.*, (users.first_name || ' ' || users.last_name) AS full_name FROM users
```

Note: If you need data from another table, use a join in a loaded value (see below).

### Standalone Datasource class

If you are going to have more complex preloading logic (like using Loaded below),
then it might be better to put Datasource code into its own class. This is pretty
easy, just create a directory `app/datasources` (or whatever you like), and create
a file depending on your model name, for example for a `Post` model, create
`post_datasource.rb`. The name is important for auto-magic reasons. Example file:

```ruby
class PostDatasource < Datasource::From(Post)
  query(:full_name) { "users.first_name || ' ' || users.last_name" }
end
```

### Loaded

You might want to have some more complex preloading logic. In that case you can
use a method to load values for all the records at once (e.g. with a custom query
or even from a cache). The loading methods are only executed if you use the values,
otherwise they will be skipped.

First just declare that you want to have a loaded attribute (the parameters will be explained shortly):

```ruby
class UserDatasource < Datasource::From(User)
  loaded :post_count, from: :array, default: 0
end
```

By default, datasource will look for a method named `load_<name>` for loading
the values, in this case `load_newest_comment`. It needs to be defined in the
collection block, which has methods to access information about the collection (posts)
that are being loaded. These methods are `scope`, `models`, `model_ids`,
`datasource`, `datasource_class` and `params`.

```ruby
class UserDatasource < Datasource::From(User)
  loaded :post_count, from: :array, default: 0

  collection do
    def load_post_count
      results = Post
        .where(user_id: model_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end
  end
end
```

In this case `load_post_count` returns an array of pairs.
For example: `[[1, 10], [2, 5]]`. Datasource can understand this because of
`from: :array`. This would result in the following:

```ruby
post_id_1.post_count # => 10
post_id_2.post_count # => 5
# other posts will have the default value or nil if no default value was given
other_post.post_count # => 0
```

Besides `default` and `from: :array`, you can also specify `group_by`, `one`
and `source`. Source is just the name of the load method.

The other two are explained in the following example.

```ruby
class PostDatasource < Datasource::From(Post)
  loaded :newest_comment, group_by: :post_id, one: true, source: :load_newest_comment

  collection do
    def load_newest_comment
      Comment.for_serializer.where(post_id: model_ids)
        .group("post_id")
        .having("id = MAX(id)")
    end
  end
end
```

In this case the load method returns an ActiveRecord relation, which for our purposes
acts the same as an Array (so we could also return an Array if we wanted).
Using `group_by: :post_id` in the `loaded` call tells datasource to group the
results in this array by that attribute (or key if it's an array of hashes instead
of model objects). `one: true` means that we only want a single value instead of
an array of values (we might want multiple, e.g. `newest_10_comments`).
So in this case, if we had a Post with id 1, `post.newest_comment` would be a
Comment from the array that has `post_id` equal to 1.

In this case, in the load method, we also used `for_serializer`, which will load
the `Comment`s according to the `CommentSerializer`.

Note that it's perfectly fine (even good) to already have a method with the same
name in your model.
If you use that method outside of serializers/datasource, it will work just as
it should. But when using datasource, it will be overwritten by the datasource
version. Counts is a good example:

```ruby
class User < ActiveRecord::Base
  has_many :posts

  def post_count
    posts.count
  end
end

class UserDatasource < Datasource::From(User)
  loaded :post_count, from: :array, default: 0

  collection do
    def load_post_count
      results = Post
        .where(user_id: model_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_count # <- post_count will be read from load_post_count
end

User.first.post_count # <- your model method will be called
```

### Params

You can also specify params that can be read from collection methods. The params
can be specified when you call `render`:

```ruby
# controller
  render json: posts,
    datasource_params: { include_newest_comments: true }

# datasource
  loaded :newest_comments, default: []

  collection do
    def load_newest_comments
      if params[:include_newest_comments]
        # ...
      end
    end
  end
```

## Getting Help

If you find a bug, please report an [Issue](https://github.com/mrbrdo/datasource/issues/new).

If you have a question, you can also open an Issue.

## Contributing

1. Fork it ( https://github.com/mrbrdo/datasource/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
