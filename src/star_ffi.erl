-module(star_ffi).

-export([create_to_file/3, list_archive/2, extract_to_dir/3, extract_to_memory/2]).

create_to_file(Path, Entries, Opts) ->
    ErlOpts = [create_option(O) || O <- Opts],
    case erl_tar:create(binary_to_list(Path), [transform_entry(E) || E <- Entries], ErlOpts) of
        ok ->
            {ok, nil};
        {error, Reason} ->
            {error, classify_error(Reason)}
    end.

transform_entry({staged_disk_path, Path}) ->
    binary_to_list(Path);
transform_entry({staged_disk_mapped, ArchivePath, DiskPath}) ->
    {binary_to_list(ArchivePath), binary_to_list(DiskPath)};
transform_entry({staged_in_memory, ArchivePath, Contents}) ->
    {binary_to_list(ArchivePath), Contents}.

create_option(create_compressed) ->
    compressed;
create_option(dereference) ->
    dereference.

extract_option(extract_compressed) ->
    compressed;
extract_option(keep_old_files) ->
    keep_old_files;
extract_option({files, Names}) ->
    {files, [binary_to_list(N) || N <- Names]}.

list_archive(Source, Opts) ->
    ErlOpts = [extract_option(O) || O <- Opts],
    case erl_tar:table(transform_source(Source), [verbose | ErlOpts]) of
        {ok, Headers} ->
            {ok, [transform_header(H) || H <- Headers]};
        {error, Reason} ->
            {error, classify_error(Reason)}
    end.

transform_header({Name, Type, Size, Mtime, Mode, Uid, Gid}) ->
    {header, to_binary(Name), to_entry_type(Type), Size, Mtime, Mode, Uid, Gid}.

to_entry_type(regular) ->
    regular;
to_entry_type(link) ->
    hard_link;
to_entry_type(symlink) ->
    symlink;
to_entry_type(char) ->
    char_device;
to_entry_type(block) ->
    block_device;
to_entry_type(directory) ->
    directory;
to_entry_type(fifo) ->
    fifo;
to_entry_type(Other) ->
    {unknown, to_binary(Other)}.

transform_source({from_file, Path}) ->
    binary_to_list(Path);
transform_source({from_data, Bytes}) ->
    {binary, Bytes}.

extract_to_dir(Source, Path, Opts) ->
    ErlOpts = [extract_option(O) || O <- Opts],
    Source0 = transform_source(Source),
    case erl_tar:extract(Source0, [{cwd, binary_to_list(Path)} | ErlOpts]) of
        ok ->
            {ok, nil};
        {error, Reason} ->
            {error, classify_error(Reason)}
    end.

extract_to_memory(Source, Opts) ->
    ErlOpts = [extract_option(O) || O <- Opts],
    TableOpts = lists:keydelete(files, 1, ErlOpts),
    Source0 = transform_source(Source),
    case erl_tar:extract(Source0, [memory | ErlOpts]) of
        {ok, Pairs} ->
            case erl_tar:table(Source0, [verbose | TableOpts]) of
                {ok, Headers} ->
                    join_entries(Pairs, Headers);
                {error, Reason} ->
                    {error, classify_error(Reason)}
            end;
        {error, Reason} ->
            {error, classify_error(Reason)}
    end.

join_entries(Pairs, VerboseHeaders) ->
    HeaderByName =
        maps:from_list([{to_binary(element(1, H)), transform_header(H)} || H <- VerboseHeaders]),
    join_entries(Pairs, HeaderByName, []).

join_entries([], _HeaderByName, Acc) ->
    {ok, lists:reverse(Acc)};
join_entries([{Name, Bin} | Rest], HeaderByName, Acc) ->
    case maps:find(to_binary(Name), HeaderByName) of
        {ok, Header} ->
            join_entries(Rest, HeaderByName, [{entry, Header, Bin} | Acc]);
        error ->
            {error, {other, <<"inconsistent archive between extract and table">>}}
    end.

to_binary(B) when is_binary(B) ->
    B;
to_binary(L) when is_list(L) ->
    iolist_to_binary(L);
to_binary(A) when is_atom(A) ->
    atom_to_binary(A, utf8).

classify_error({Name, enoent}) ->
    {file_not_found, to_binary(Name)};
classify_error({Name, eacces}) ->
    {permission_denied, to_binary(Name)};
classify_error(eof) ->
    unexpected_eof;
classify_error(bad_header) ->
    bad_header;
classify_error({unsupported, Reason}) ->
    {unsupported, to_binary(Reason)};
classify_error(Other) ->
    {other, iolist_to_binary(erl_tar:format_error(Other))}.
