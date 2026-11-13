# pre-commit hook `juliaformatter`: format the given Julia files with the JuliaFormatter
# pinned in tools/format, using the options in .JuliaFormatter.toml (BlueStyle).
#
#   julia --startup-file=no --project=tools/format scripts/dev/format.jl FILE...
#
# Exits 1 if any file was changed, so the commit stops and you can review the changes,
# `git add` them and commit again. Instantiates tools/format on first use.

try
    using JuliaFormatter
catch
    using Pkg
    Pkg.instantiate()
    using JuliaFormatter
end

files = filter(f -> endswith(f, ".jl"), ARGS)
isempty(files) && exit(0)

# format() returns true when every file was already formatted. It looks up
# .JuliaFormatter.toml from each file's folder upwards, unlike format_file().
if format(files)
    exit(0)
else
    println(stderr, "JuliaFormatter reformatted some files. Review the changes, `git add` them and commit again.")
    exit(1)
end
