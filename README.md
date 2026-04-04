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

## TODO: Implement file/image upload
- [ ] Buat migration `post_images` dengan `post_id`, `role`, `url`, `filename`, `content_type`, `size`, dan `timestamps`
- [ ] Buat schema `Appsatu.Blog.PostImage`
- [ ] Tambahkan `has_many :images, Appsatu.Blog.PostImage` ke `Appsatu.Blog.Post`
- [ ] Ubah form `post_form.html.heex` menjadi `multipart/form-data`
- [ ] Tambahkan input file ke form (`cover_image`, `thumbnail_image`, `gallery_images[]`, atau `attachment`)
- [ ] Tangani `Plug.Upload` di `PostController` untuk `create` dan `update`
- [ ] Simpan file upload ke lokasi sementara (dev: `priv/static/uploads` atau `uploads`)
- [ ] Gunakan nama file unik seperti `Ecto.UUID.generate() <> extension`
- [ ] Simpan metadata file di database, bukan isi file
- [ ] Tampilkan gambar/file di view `show` / `index`
- [ ] Tambahkan validasi file type dan ukuran

## FILE / IMAGE UPLOAD

### Dasar yang harus diikuti
- Validasi tipe file: misalnya `image/jpeg`, `image/png`, `image/webp`, dsb.
- Validasi ukuran file maksimal.
- Jangan percaya nama file dari klien.
- Beri nama file unik: contoh `UUID + extension`.
- Simpan file final di storage yang persisten; gunakan folder `uploads` hanya untuk cache/temporary.
- Simpan metadata file di database, bukan isi file.

### Struktur data yang disarankan
- `Post` = data tulisan.
- `PostImage` / `Asset` = metadata file.
- Gunakan `has_many` agar satu `Post` bisa punya banyak file/gambar.
- Gunakan `role` atau `type` untuk membedakan `cover`, `thumbnail`, `gallery`, `attachment`, dsb.

### Flow upload yang disarankan
- Form harus `multipart/form-data`.
- Tangani upload dengan `Plug.Upload` di controller/context.
- Simpan file lokal untuk development; untuk production gunakan storage eksternal.
- Simpan hanya `url`/`object_key` + metadata di DB.

### Catatan
- Untuk UX modern, pertimbangkan `Phoenix.LiveView` upload nanti.
- Jika suatu saat menggunakan multi-tenant, pakai key/URL unik per tenant.
