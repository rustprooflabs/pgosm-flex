# Building doc book

The book is built [using `mdbook`](https://rust-lang.github.io/mdBook/index.html).

Install mdbook.

```bash
cargo install mdbook
cargo install mdbook-variables
```

Serve the book locally and open your default browser.

```bash
cd docs
mdbook serve --open
```