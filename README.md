# Datasource

Automatically preload your ORM records for your serializer.

## Install

Add to Gemfile

```
gem 'datasource'
```

And `bundle install`.

Run install generator:

```
rails g datasource:install
```

#### ORM support

- ActiveRecord
- Sequel

#### Serializer support

- active_model_serializers

## Basic Usage

### Attributes
You don't have to do anything special.

```ruby
class UserSerializer < ActiveModel::Serializer
  attributes :id, :email
end
```

But you get an optimized query for free:

```sql
SELECT id, email FROM users
```

### Associations
You don't have to do anything special.

```ruby
class PostSerializer < ActiveModel::Serializer
  attributes :id, :title
end

class UserSerializer < ActiveModel::Serializer
  attributes :id
  has_many :posts
end
```

But you get automatic association preloading ("includes") with optimized queries for free:

```sql
SELECT id FROM users
SELECT id, title, user_id FROM posts WHERE id IN (?)
```

### Model Methods / Virtual Attributes
You need to use `computed` in a `datasource_module` block to specify what a method depends on. It can depend on database columns, other computed attributes or loaders.

```ruby
class User < ActiveRecord::Base
  datasource_module do
    computed :first_name_initial, :first_name
    computed :both_initials, :first_name, :last_name
  end

  # method can be in model
  def first_name_initial
    first_name[0].upcase
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :first_name_initial, :last_name_initial

  # method can also be in serializer
  def both_initials
    object.last_name[0].upcase + object.last_name[0].upcase
  end
end
```

```sql
SELECT first_name, last_name FROM users
```

You will be reminded with an exception if you forget to do this.

### Show action

You will probably want to reuse the same preloading logic in your show action.
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

## Advanced Usage

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
SELECT users.id, (users.first_name || ' ' || users.last_name) AS full_name FROM users
```

Note: If you need data from another table, use a join in a loader (see below).

### Loader

You might want to have some more complex preloading logic. In that case you can use a loader.
A loader will receive ids of the records, and needs to return a hash.
The key of the hash must be the id of the record for which the value is.

A loader will only be executed if a computed attribute depends on it. If an attribute depends
on multiple loaders, pass an array of loaders like so `computed :attr, loaders: [:loader1, :loader2]`.

Be careful that if your hash does not contain a value for the object ID, the loaded value
will be nil. However you can use the `default` option for such cases (see below example).

```ruby
class User < ActiveRecord::Base
  datasource_module do
    computed :post_count, loader: :post_counts
    loader :post_counts, array_to_hash: true, default: 0 do |user_ids|
      results = Post
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_count

  def post_count
    # Will automatically give you the value for this user's ID
    object.loaded_values[:post_counts]
  end
end
```

```sql
SELECT users.id FROM users
SELECT user_id, COUNT(id) FROM posts WHERE user_id IN (?)
```

Datasource provides shortcuts to transform your data into a hash. Here are examples:

```ruby
loader :stuff, array_to_hash: true do |ids|
  [[1, "first"], [2, "second"]]
  # will be transformed into
  # { 1 => "first", 2 => "second" }
end

loader :stuff, group_by: :user_id do |ids|
  Post.where(user_id: ids)
  # will be transformed into
  # { 1 => [#<Post>, #<Post>, ...], 2 => [ ... ], ... }
end

loader :stuff, group_by: :user_id, one: true do |ids|
  Post.where(user_id: ids)
  # will be transformed into
  # { 1 => #<Post>, 2 => #<Post>, ... }
end

loader :stuff, group_by: "user_id", one: true do |ids|
  # it works the same way on an array of hashes
  # but be careful about Symbol/String difference
  [{ "title" => "Something", "user_id" => 10 }]
  # will be transformed into
  # { 10 => { "title" => "Something", "user_id" => 10 } }
end
```

### Loaded

Loaded is the same as loader, but it also creates a computed attribute and defines
a method with the same name on your model.

Here is the previous example with `loaded` instead of `loader`:

```ruby
class User < ActiveRecord::Base
  datasource_module do
    loaded :post_count, array_to_hash: true, default: 0 do |user_ids|
      results = Post
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_count
  # Note that the User now has a generated post_count method
end
```

When using `loaded`, if you already have the method with this name defined in your
model, datasource will automatically create a 'wrapper' method that will use the
loaded value if available (when you are using a serializer/datasource), otherwise
it will fallback to your original method. This way you can still use the same
method when you are not using a serializer/datasource. For example:

```ruby
class User < ActiveRecord::Base
  datasource_module do
    loaded :post_count, array_to_hash: true, default: 0 do |user_ids|
      results = Post
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end

    def post_count
      posts.count
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_count # <- post_count will be read from loaded_values
end

User.first.post_count # <- your method will be called

```
