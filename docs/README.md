# Building doc book

The book is built [using `mdbook`](https://rust-lang.github.io/mdBook/index.html).

Install mdbook.

```bash
cargo install mdbook --version 0.4.32
cargo install mdbook-variables --version 0.2.2
```

Serve the book locally and open your default browser.

```bash
cd docs
mdbook serve --open
```