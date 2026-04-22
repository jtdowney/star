//// Gleam bindings for Erlang's [`erl_tar`](https://www.erlang.org/doc/apps/stdlib/erl_tar.html)
//// to create, extract, and list tar archives with optional gzip compression.
////
//// Archives can be read from a file or from an in-memory `BitArray`
//// (see `ArchiveSource`), but building is file-only.

import gleam/list
import gleam/result

/// Where to read an archive from.
pub type ArchiveSource {
  /// Read the archive from a file at `path`.
  FromFile(path: String)
  /// Read the archive from an in-memory bit array.
  FromData(contents: BitArray)
}

/// Accumulator for building an archive.
pub opaque type Builder {
  Builder(entries: List(BuilderEntry), follow_symlinks: Bool)
}

type BuilderEntry {
  StagedDiskPath(path: String)
  StagedDiskMapped(archive_path: String, disk_path: String)
  StagedInMemory(name: String, contents: BitArray)
}

/// Whether an archive is plain or gzipped.
pub type Compression {
  /// Plain, uncompressed tar (`.tar`).
  Uncompressed
  /// Gzip-compressed tar (`.tar.gz`).
  Gzip
}

/// A single entry comprising its header and raw byte contents.
pub type Entry {
  Entry(header: Header, contents: BitArray)
}

/// The kind of entry represented by a tar header.
pub type EntryType {
  /// Ordinary file with byte contents.
  Regular
  /// Hard link to another entry within the archive.
  HardLink
  /// Symbolic link. `list` reports the header (with `size == 0`), but the
  /// link target is not surfaced. `extract_memory` omits symlink entries
  /// entirely; use `extract` to reproduce them on disk.
  Symlink
  /// Character special device.
  CharDevice
  /// Block special device.
  BlockDevice
  /// Directory entry with no contents.
  Directory
  /// Named pipe (FIFO).
  Fifo
  /// Type flag `erl_tar` reported that `star` does not recognise.
  Unknown(tag: String)
}

type CreateOption {
  CreateCompressed
  Dereference
}

type ExtractOption {
  ExtractCompressed
  KeepOldFiles
  Files(names: List(String))
}

/// Error returned from any `star` operation.
pub type Error {
  /// Archive contains a malformed header block.
  BadHeader
  /// Archive stream ended before a complete entry was read.
  UnexpectedEof
  /// Referenced path does not exist on disk.
  FileNotFound(path: String)
  /// Operating system denied access to the given path.
  PermissionDenied(path: String)
  /// Encountered a tar feature `star` does not handle;
  /// `reason` echoes the underlying tag.
  Unsupported(reason: String)
  /// Catch-all for `erl_tar` errors that do not map to a specific
  /// variant; `message` is the formatted human-readable description.
  Other(message: String)
}

/// Which entries an `extract` or `list` call should act on.
pub type Filter {
  /// Act on every entry in the archive.
  AllEntries
  /// Act only on entries whose `name` appears in the list; names
  /// missing from the archive are ignored.
  Only(names: List(String))
}

/// What `extract` should do when an entry would land on a path that
/// already exists on disk.
pub type OnConflict {
  /// Replace the existing file with the archive entry.
  Overwrite
  /// Leave the existing file alone and continue extracting other entries.
  Skip
}

/// Metadata for an archive entry.
pub type Header {
  Header(
    /// Name of the entry as stored in the archive.
    name: String,
    /// Kind of entry (regular file, directory, symlink, etc.).
    entry_type: EntryType,
    /// Size of the contents in bytes.
    size: Int,
    /// Modification time as Unix epoch seconds.
    mtime: Int,
    /// Unix permission bits, e.g. `0o644`.
    mode: Int,
    /// Numeric user id of the entry's owner.
    uid: Int,
    /// Numeric group id of the entry's owner.
    gid: Int,
  )
}

/// Stage a file on disk under a different name in the archive.
pub fn add_disk_mapped(
  builder: Builder,
  at archive_path: String,
  from disk_path: String,
) -> Builder {
  stage(builder, StagedDiskMapped(archive_path, disk_path))
}

/// Stage a file on disk. The provided path is used verbatim as both the
/// source path on disk and the entry name in the archive; pass a
/// relative path unless you want absolute paths embedded in the archive.
/// The file's real on-disk type (regular file, directory, symlink, etc.)
/// is preserved.
pub fn add_disk_path(builder: Builder, from path: String) -> Builder {
  stage(builder, StagedDiskPath(path))
}

/// Stage an in-memory file entry with mode `0o644`.
pub fn add_file(
  builder: Builder,
  at path: String,
  containing contents: BitArray,
) -> Builder {
  stage(builder, StagedInMemory(path, contents))
}

/// Finalise the builder into a tar archive written to `path`.
pub fn build_file(
  builder: Builder,
  at path: String,
  compression compression: Compression,
) -> Result(Nil, Error) {
  let opts = build_create_options(compression, builder.follow_symlinks)
  create_to_file(path, list.reverse(builder.entries), opts)
}

/// When `True`, symlinks encountered by `add_disk_path` or
/// `add_disk_mapped` are archived as their target contents rather than as
/// link entries. Defaults to `False`.
pub fn follow_symlinks(builder: Builder, enabled: Bool) -> Builder {
  Builder(..builder, follow_symlinks: enabled)
}

/// Start a new, empty `Builder`.
pub fn new() -> Builder {
  Builder(entries: [], follow_symlinks: False)
}

fn build_create_options(
  compression: Compression,
  follow_symlinks: Bool,
) -> List(CreateOption) {
  let opts = case follow_symlinks {
    True -> [Dereference]
    False -> []
  }
  case compression {
    Gzip -> [CreateCompressed, ..opts]
    Uncompressed -> opts
  }
}

fn stage(builder: Builder, entry: BuilderEntry) -> Builder {
  Builder(..builder, entries: [entry, ..builder.entries])
}

@external(erlang, "star_ffi", "create_to_file")
fn create_to_file(
  path: String,
  entries: List(BuilderEntry),
  opts: List(CreateOption),
) -> Result(Nil, Error)

/// Extract every entry (or a filtered subset) from an archive onto disk
/// under `path`. `on_conflict` decides what happens when an entry would
/// land on a path that already exists.
pub fn extract(
  from source: ArchiveSource,
  to path: String,
  compression compression: Compression,
  filter filter: Filter,
  on_conflict on_conflict: OnConflict,
) -> Result(Nil, Error) {
  let opts = build_extract_options(compression, filter, on_conflict)
  extract_archive_to_dir(source, path, opts)
}

/// Extract entries from an archive into an in-memory list of `Entry`
/// values, in archive order. Non-regular entries (symlinks, hard links,
/// devices, fifos, directories) are omitted from the result; use
/// `extract` to reproduce them on disk, or `list` to see their headers.
///
/// The archive is parsed twice (once for contents, once for headers), so
/// gzipped sources are decoded twice. Prefer `extract` for large archives.
pub fn extract_memory(
  from source: ArchiveSource,
  compression compression: Compression,
  filter filter: Filter,
) -> Result(List(Entry), Error) {
  let opts = compression_to_opts(compression)
  let opts = case filter {
    AllEntries -> opts
    Only(names) -> [Files(names), ..opts]
  }
  extract_archive_to_memory(source, opts)
}

fn compression_to_opts(compression: Compression) -> List(ExtractOption) {
  case compression {
    Gzip -> [ExtractCompressed]
    Uncompressed -> []
  }
}

fn apply_filter(
  items: List(a),
  filter: Filter,
  name name: fn(a) -> String,
) -> List(a) {
  case filter {
    AllEntries -> items
    Only(names) ->
      list.filter(items, fn(item) { list.contains(names, name(item)) })
  }
}

fn build_extract_options(
  compression: Compression,
  filter: Filter,
  on_conflict: OnConflict,
) -> List(ExtractOption) {
  let opts = compression_to_opts(compression)
  let opts = case on_conflict {
    Skip -> [KeepOldFiles, ..opts]
    Overwrite -> opts
  }
  case filter {
    AllEntries -> opts
    Only(names) -> [Files(names), ..opts]
  }
}

@external(erlang, "star_ffi", "extract_to_dir")
fn extract_archive_to_dir(
  source: ArchiveSource,
  path: String,
  opts: List(ExtractOption),
) -> Result(Nil, Error)

@external(erlang, "star_ffi", "extract_to_memory")
fn extract_archive_to_memory(
  source: ArchiveSource,
  opts: List(ExtractOption),
) -> Result(List(Entry), Error)

/// List the headers of every entry in an archive, optionally filtered
/// to a subset of names.
pub fn list(
  from source: ArchiveSource,
  compression compression: Compression,
  filter filter: Filter,
) -> Result(List(Header), Error) {
  list_archive(source, compression_to_opts(compression))
  |> result.map(apply_filter(_, filter, name: fn(h: Header) { h.name }))
}

@external(erlang, "star_ffi", "list_archive")
fn list_archive(
  source: ArchiveSource,
  opts: List(ExtractOption),
) -> Result(List(Header), Error)
