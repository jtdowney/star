import gleam/list
import qcheck
import simplifile
import star
import temporary
import unitest

pub fn main() -> Nil {
  unitest.main()
}

fn with_temp_dir(k: fn(String) -> Nil) -> Nil {
  let assert Ok(Nil) = temporary.create(temporary.directory(), k)
  Nil
}

fn file_input() -> qcheck.Generator(#(String, BitArray)) {
  qcheck.tuple2(
    qcheck.non_empty_string_from(qcheck.alphanumeric_ascii_codepoint()),
    qcheck.non_empty_byte_aligned_bit_array(),
  )
}

fn build_fixture(path: String, compression: star.Compression) -> Nil {
  let assert Ok(Nil) =
    star.new()
    |> star.add_file(at: "a.txt", containing: <<"alpha":utf8>>)
    |> star.add_file(at: "b.txt", containing: <<"beta":utf8>>)
    |> star.add_file(at: "c.txt", containing: <<"gamma":utf8>>)
    |> star.build_file(at: path, compression: compression)
  Nil
}

pub fn disk_roundtrip_gzip_test() {
  disk_roundtrip(star.Gzip, "archive.tar.gz")
}

pub fn disk_roundtrip_uncompressed_test() {
  disk_roundtrip(star.Uncompressed, "archive.tar")
}

fn disk_roundtrip(compression: star.Compression, archive_name: String) {
  use dir <- with_temp_dir
  let source_dir = dir <> "/source"
  let extract_dir = dir <> "/extracted"
  let archive_path = dir <> "/" <> archive_name
  let source_file = source_dir <> "/note.txt"
  let source_contents = "disk roundtrip payload"

  let assert Ok(Nil) = simplifile.create_directory_all(source_dir)
  let assert Ok(Nil) = simplifile.create_directory_all(extract_dir)
  let assert Ok(Nil) = simplifile.write(source_file, source_contents)

  let assert Ok(Nil) =
    star.new()
    |> star.add_disk_mapped(at: "note.txt", from: source_file)
    |> star.build_file(at: archive_path, compression: compression)

  let assert Ok(Nil) =
    star.extract(
      from: star.FromFile(archive_path),
      to: extract_dir,
      compression: compression,
      filter: star.AllEntries,
      on_conflict: star.Overwrite,
    )

  let assert Ok(round_tripped) = simplifile.read(extract_dir <> "/note.txt")
  assert round_tripped == source_contents
}

pub fn add_disk_path_roundtrip_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let source_file = dir <> "/note.txt"
  let source_contents = "add_disk_path payload"

  let assert Ok(Nil) = simplifile.write(source_file, source_contents)

  let assert Ok(Nil) =
    star.new()
    |> star.add_disk_path(from: source_file)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )

  let assert [entry] = entries
  assert entry.header.name == source_file
  assert entry.contents == <<"add_disk_path payload":utf8>>
}

pub fn add_disk_path_directory_produces_directory_header_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let source_dir = dir <> "/staged"
  let assert Ok(Nil) = simplifile.create_directory_all(source_dir)

  let assert Ok(Nil) =
    star.new()
    |> star.add_disk_path(from: source_dir)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )

  let assert [header] = headers
  assert header.entry_type == star.Directory
}

pub fn empty_archive_roundtrip_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let assert Ok(Nil) =
    star.new()
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  assert entries == []
}

pub fn extract_memory_filter_restricts_to_named_entries_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  build_fixture(archive_path, star.Uncompressed)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.Only(["a.txt", "c.txt"]),
    )
  assert list.map(entries, fn(entry) { entry.header.name })
    == ["a.txt", "c.txt"]
}

pub fn extract_memory_returns_contents_and_headers_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let assert Ok(Nil) =
    star.new()
    |> star.add_file(at: "a.txt", containing: <<"alpha":utf8>>)
    |> star.add_file(at: "b.txt", containing: <<"beta":utf8>>)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )

  let pairs =
    list.map(entries, fn(entry) { #(entry.header.name, entry.contents) })
  assert pairs == [#("a.txt", <<"alpha":utf8>>), #("b.txt", <<"beta":utf8>>)]
}

pub fn extract_memory_reads_gzip_archive_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar.gz"
  build_fixture(archive_path, star.Gzip)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Gzip,
      filter: star.AllEntries,
    )

  let pairs =
    list.map(entries, fn(entry) { #(entry.header.name, entry.contents) })
  assert pairs
    == [
      #("a.txt", <<"alpha":utf8>>),
      #("b.txt", <<"beta":utf8>>),
      #("c.txt", <<"gamma":utf8>>),
    ]
}

pub fn extract_filter_restricts_to_named_entries_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let extract_dir = dir <> "/extracted"
  let assert Ok(Nil) = simplifile.create_directory_all(extract_dir)
  build_fixture(archive_path, star.Uncompressed)

  let assert Ok(Nil) =
    star.extract(
      from: star.FromFile(archive_path),
      to: extract_dir,
      compression: star.Uncompressed,
      filter: star.Only(["a.txt", "c.txt"]),
      on_conflict: star.Overwrite,
    )

  let assert Ok(a_contents) = simplifile.read(extract_dir <> "/a.txt")
  let assert Ok(c_contents) = simplifile.read(extract_dir <> "/c.txt")
  assert a_contents == "alpha"
  assert c_contents == "gamma"
  assert simplifile.is_file(extract_dir <> "/b.txt") == Ok(False)
}

pub fn extract_missing_file_returns_file_not_found_test() {
  let assert Error(star.FileNotFound(_)) =
    star.extract_memory(
      from: star.FromFile("/does/not/exist/star-missing.tar"),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
}

pub fn extract_malformed_bytes_returns_error_test() {
  let assert Error(error) =
    star.extract_memory(
      from: star.FromData(<<"not a real tar archive":utf8>>),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  case error {
    star.BadHeader | star.UnexpectedEof | star.Other(_) -> Nil
    star.FileNotFound(_) | star.PermissionDenied(_) | star.Unsupported(_) ->
      panic as "unexpected error variant for malformed bytes"
  }
}

pub fn extract_from_bytes_returns_entries_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  build_fixture(archive_path, star.Uncompressed)
  let assert Ok(bytes) = simplifile.read_bits(archive_path)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromData(bytes),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  assert list.map(entries, fn(entry) { entry.header.name })
    == ["a.txt", "b.txt", "c.txt"]
}

pub fn extract_from_bytes_extracts_to_disk_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let extract_dir = dir <> "/extracted"
  let assert Ok(Nil) = simplifile.create_directory_all(extract_dir)
  build_fixture(archive_path, star.Uncompressed)
  let assert Ok(bytes) = simplifile.read_bits(archive_path)

  let assert Ok(Nil) =
    star.extract(
      from: star.FromData(bytes),
      to: extract_dir,
      compression: star.Uncompressed,
      filter: star.AllEntries,
      on_conflict: star.Overwrite,
    )

  let assert Ok(a_contents) = simplifile.read(extract_dir <> "/a.txt")
  let assert Ok(b_contents) = simplifile.read(extract_dir <> "/b.txt")
  let assert Ok(c_contents) = simplifile.read(extract_dir <> "/c.txt")
  assert a_contents == "alpha"
  assert b_contents == "beta"
  assert c_contents == "gamma"
}

pub fn extract_skip_preserves_existing_file_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let extract_dir = dir <> "/extracted"
  let assert Ok(Nil) = simplifile.create_directory_all(extract_dir)
  let assert Ok(Nil) = simplifile.write(extract_dir <> "/a.txt", "original")

  let assert Ok(Nil) =
    star.new()
    |> star.add_file(at: "a.txt", containing: <<"replaced":utf8>>)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(Nil) =
    star.extract(
      from: star.FromFile(archive_path),
      to: extract_dir,
      compression: star.Uncompressed,
      filter: star.AllEntries,
      on_conflict: star.Skip,
    )

  let assert Ok(contents) = simplifile.read(extract_dir <> "/a.txt")
  assert contents == "original"
}

pub fn extract_overwrite_replaces_existing_file_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let extract_dir = dir <> "/extracted"
  let assert Ok(Nil) = simplifile.create_directory_all(extract_dir)
  let assert Ok(Nil) = simplifile.write(extract_dir <> "/a.txt", "original")

  let assert Ok(Nil) =
    star.new()
    |> star.add_file(at: "a.txt", containing: <<"replaced":utf8>>)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(Nil) =
    star.extract(
      from: star.FromFile(archive_path),
      to: extract_dir,
      compression: star.Uncompressed,
      filter: star.AllEntries,
      on_conflict: star.Overwrite,
    )

  let assert Ok(contents) = simplifile.read(extract_dir <> "/a.txt")
  assert contents == "replaced"
}

pub fn extract_only_with_skip_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let extract_dir = dir <> "/extracted"
  let assert Ok(Nil) = simplifile.create_directory_all(extract_dir)
  let assert Ok(Nil) = simplifile.write(extract_dir <> "/a.txt", "original")
  build_fixture(archive_path, star.Uncompressed)

  let assert Ok(Nil) =
    star.extract(
      from: star.FromFile(archive_path),
      to: extract_dir,
      compression: star.Uncompressed,
      filter: star.Only(["a.txt", "b.txt"]),
      on_conflict: star.Skip,
    )

  let assert Ok(a_contents) = simplifile.read(extract_dir <> "/a.txt")
  let assert Ok(b_contents) = simplifile.read(extract_dir <> "/b.txt")
  assert a_contents == "original"
  assert b_contents == "beta"
  assert simplifile.is_file(extract_dir <> "/c.txt") == Ok(False)
}

pub fn list_filter_restricts_to_named_entries_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  build_fixture(archive_path, star.Uncompressed)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.Only(["a.txt", "c.txt"]),
    )
  assert list.map(headers, fn(header) { header.name }) == ["a.txt", "c.txt"]
}

pub fn list_filter_ignores_missing_names_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  build_fixture(archive_path, star.Uncompressed)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.Only(["a.txt", "ghost.txt"]),
    )
  assert list.map(headers, fn(header) { header.name }) == ["a.txt"]
}

pub fn list_returns_headers_in_archive_order_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let assert Ok(Nil) =
    star.new()
    |> star.add_file(at: "a.txt", containing: <<"alpha":utf8>>)
    |> star.add_file(at: "b.txt", containing: <<"beta":utf8>>)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  assert list.map(headers, fn(header) { header.name }) == ["a.txt", "b.txt"]
}

pub fn list_from_bytes_returns_headers_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  build_fixture(archive_path, star.Uncompressed)
  let assert Ok(bytes) = simplifile.read_bits(archive_path)

  let assert Ok(headers) =
    star.list(
      from: star.FromData(bytes),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  assert list.map(headers, fn(header) { header.name })
    == ["a.txt", "b.txt", "c.txt"]
}

pub fn list_reads_gzip_archive_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar.gz"
  build_fixture(archive_path, star.Gzip)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Gzip,
      filter: star.AllEntries,
    )
  assert list.map(headers, fn(header) { header.name })
    == ["a.txt", "b.txt", "c.txt"]
}

pub fn fixture_header_fields_match_known_values_test() {
  let assert Ok(headers) =
    star.list(
      from: star.FromFile("test/fixtures/known.tar"),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  let assert [header] = headers
  assert header.name == "hello.txt"
  assert header.entry_type == star.Regular
  assert header.size == 5
  assert header.mode == 0o644
  assert header.uid == 0
  assert header.gid == 0
  assert header.mtime == 1_767_225_600
}

pub fn list_empty_archive_returns_empty_list_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let assert Ok(Nil) =
    star.new()
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  assert headers == []
}

pub fn symlink_is_visible_in_list_but_omitted_from_memory_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let target_path = dir <> "/target.txt"
  let symlink_path = dir <> "/link.txt"

  let assert Ok(Nil) = simplifile.write(target_path, "payload")
  let assert Ok(Nil) =
    simplifile.create_symlink(to: target_path, from: symlink_path)

  let assert Ok(Nil) =
    star.new()
    |> star.add_disk_mapped(at: "link.txt", from: symlink_path)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(headers) =
    star.list(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  let assert [header] = headers
  assert header.name == "link.txt"
  assert header.entry_type == star.Symlink
  assert header.size == 0

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )
  assert entries == []
}

pub fn follow_symlinks_archives_target_contents_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let target_path = dir <> "/target.txt"
  let symlink_path = dir <> "/link.txt"
  let target_contents = "dereferenced payload"

  let assert Ok(Nil) = simplifile.write(target_path, target_contents)
  let assert Ok(Nil) =
    simplifile.create_symlink(to: target_path, from: symlink_path)

  let assert Ok(Nil) =
    star.new()
    |> star.follow_symlinks(True)
    |> star.add_disk_mapped(at: "link.txt", from: symlink_path)
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )

  let assert [entry] = entries
  assert entry.header.entry_type == star.Regular
  assert entry.contents == <<"dereferenced payload":utf8>>
}

pub fn roundtrip_preserves_names_and_contents_test() {
  use dir <- with_temp_dir
  let archive_path = dir <> "/archive.tar"
  let config = qcheck.default_config() |> qcheck.with_test_count(25)
  use inputs <- qcheck.run(config, qcheck.list_from(file_input()))

  let assert Ok(Nil) =
    inputs
    |> list.fold(star.new(), fn(builder, input) {
      star.add_file(builder, at: input.0, containing: input.1)
    })
    |> star.build_file(at: archive_path, compression: star.Uncompressed)

  let assert Ok(entries) =
    star.extract_memory(
      from: star.FromFile(archive_path),
      compression: star.Uncompressed,
      filter: star.AllEntries,
    )

  let got =
    list.map(entries, fn(entry) { #(entry.header.name, entry.contents) })
  assert got == inputs
}
