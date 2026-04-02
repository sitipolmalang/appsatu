# Appsatu

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix


## Controller example
GET     /                                      AppsatuWeb.PageController :home
GET     /posts                                 AppsatuWeb.PostController :index
GET     /posts/:id/edit                        AppsatuWeb.PostController :edit
GET     /posts/new                             AppsatuWeb.PostController :new
GET     /posts/:id                             AppsatuWeb.PostController :show
POST    /posts                                 AppsatuWeb.PostController :create
PATCH   /posts/:id                             AppsatuWeb.PostController :update
PUT     /posts/:id                             AppsatuWeb.PostController :update
DELETE  /posts/:id                             AppsatuWeb.PostController :delete
