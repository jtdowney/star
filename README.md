# star

[![Package Version](https://img.shields.io/hexpm/v/star)](https://hex.pm/packages/star)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/star/)

Gleam bindings for Erlang's [`erl_tar`](https://www.erlang.org/doc/apps/stdlib/erl_tar.html)
to create, extract, and list tar archives with optional gzip compression.

```sh
gleam add star
```

## Creating an archive

Use the builder to stage entries, then write to a file:

```gleam
import star

pub fn main() {
  let assert Ok(Nil) =
    star.new()
    |> star.add_file(at: "hello.txt", containing: <<"hi":utf8>>)
    |> star.add_disk_path(from: "README.md")
    |> star.add_disk_mapped(at: "bin/tool", from: "build/tool")
    |> star.build_file(at: "release.tar.gz", compression: star.Gzip)
}
```

## Extracting an archive

```gleam
star.extract(
  from: star.FromFile("release.tar.gz"),
  to: "/tmp/release",
  compression: star.Gzip,
  filter: star.AllEntries,
  on_conflict: star.Overwrite,
)
```

Extract into memory instead:

```gleam
let assert Ok(entries) =
  star.extract_memory(
    from: star.FromFile("release.tar.gz"),
    compression: star.Gzip,
    filter: star.Only(["README.md", "bin/tool"]),
  )
```

## Listing an archive

```gleam
let assert Ok(headers) =
  star.list(
    from: star.FromFile("release.tar.gz"),
    compression: star.Gzip,
    filter: star.AllEntries,
  )
```
