# A small, dependency-free CSV reader that copes with the quirks of the input files
# (finding F-24): UTF-8 byte-order marks, CRLF and CR-only (classic Mac) line endings,
# Latin-1 bytes in free-text columns, quoted fields with embedded commas, and a missing
# final newline. Every cell is kept as a String; typed parsing happens in the callers,
# so that error messages can name the file, line and column.

"""
    CSVTable

Header and rows of a CSV file, all cells as `String`. Use [`column`](@ref) and
[`numeric_column`](@ref) to extract data.
"""
struct CSVTable
    path::String
    header::Vector{String}
    rows::Vector{Vector{String}}
end

Base.length(t::CSVTable) = length(t.rows)

"""
    read_csv_table(path) -> CSVTable

Read a comma-separated file with a header line. Blank lines are skipped. Rows with a
different number of fields than the header raise an `ArgumentError`.
"""
function read_csv_table(path::AbstractString)
    isfile(path) || throw(ArgumentError("file not found: $path"))
    bytes = read(path)
    # strip a UTF-8 byte-order mark
    if length(bytes) >= 3 && bytes[1] == 0xef && bytes[2] == 0xbb && bytes[3] == 0xbf
        bytes = bytes[4:end]
    end
    records = _split_records(bytes)
    isempty(records) && throw(ArgumentError("$path: the file is empty"))
    header = [strip(h) for h in records[1][2]]
    any(isempty, header) && throw(ArgumentError("$path: empty column name in the header"))
    length(unique(header)) == length(header) ||
        throw(ArgumentError("$path: duplicate column names in the header"))
    rows = Vector{Vector{String}}()
    for (lineno, fields) in records[2:end]
        if length(fields) == 1 && isempty(strip(fields[1]))
            continue
        end
        length(fields) == length(header) || throw(ArgumentError(
            "$path:$lineno: expected $(length(header)) fields, found $(length(fields))"))
        push!(rows, fields)
    end
    return CSVTable(String(path), String.(header), rows)
end

# Split raw bytes into (line number, fields) records. Handles quotes ("" escapes),
# CRLF / CR / LF line endings and a missing trailing newline.
function _split_records(bytes::Vector{UInt8})
    records = Tuple{Int,Vector{String}}[]
    fields = String[]
    buf = UInt8[]
    inquotes = false
    line = 1
    recline = 1
    i = 1
    n = length(bytes)
    while i <= n
        b = bytes[i]
        if inquotes
            if b == UInt8('"')
                if i < n && bytes[i+1] == UInt8('"')
                    push!(buf, b)
                    i += 1
                else
                    inquotes = false
                end
            else
                (b == UInt8('\n') || b == UInt8('\r')) && (line += 1)
                push!(buf, b)
            end
        elseif b == UInt8('"')
            inquotes = true
        elseif b == UInt8(',')
            push!(fields, String(copy(buf)))
            empty!(buf)
        elseif b == UInt8('\n') || b == UInt8('\r')
            push!(fields, String(copy(buf)))
            empty!(buf)
            push!(records, (recline, fields))
            fields = String[]
            if b == UInt8('\r') && i < n && bytes[i+1] == UInt8('\n')
                i += 1
            end
            line += 1
            recline = line
        else
            push!(buf, b)
        end
        i += 1
    end
    inquotes && throw(ArgumentError("unterminated quoted field starting on line $recline"))
    if !isempty(buf) || !isempty(fields)
        push!(fields, String(copy(buf)))
        push!(records, (recline, fields))
    end
    return records
end

"""
    has_column(t::CSVTable, name) -> Bool
"""
has_column(t::CSVTable, name::AbstractString) = name in t.header

function _colindex(t::CSVTable, name::AbstractString)
    j = findfirst(==(name), t.header)
    j === nothing && throw(ArgumentError("$(t.path): required column '$name' not found " *
                                         "(columns: $(join(t.header, ", ")))"))
    return j
end

"""
    column(t::CSVTable, name) -> Vector{String}

The raw (stripped) cells of a column.
"""
column(t::CSVTable, name::AbstractString) = [String(strip(r[_colindex(t, name)])) for r in t.rows]

const _MISSING_TOKENS = ("", "NA", "na", "N/A", "missing")

"""
    parse_number(s; allow_missing = false) -> Float64

Parse a numeric cell. Accepts `inf`, `Inf`, `-inf` and the legacy `_inf` (minus
infinity) used in the prior CSV files. Empty cells and `NA` become `NaN` when
`allow_missing = true` and raise an error otherwise.
"""
function parse_number(s::AbstractString; allow_missing::Bool = false)
    x = strip(s)
    if x in _MISSING_TOKENS
        allow_missing && return NaN
        throw(ArgumentError("missing value"))
    end
    lx = lowercase(x)
    lx in ("inf", "+inf", "infinity") && return Inf
    lx in ("-inf", "_inf", "-infinity") && return -Inf
    lx == "nan" && return NaN
    v = tryparse(Float64, x)
    v === nothing && throw(ArgumentError("cannot parse '$x' as a number"))
    return v
end

"""
    numeric_column(t::CSVTable, name; allow_missing = false) -> Vector{Float64}
"""
function numeric_column(t::CSVTable, name::AbstractString; allow_missing::Bool = false)
    j = _colindex(t, name)
    out = Vector{Float64}(undef, length(t.rows))
    for (r, row) in enumerate(t.rows)
        try
            out[r] = parse_number(row[j]; allow_missing = allow_missing)
        catch err
            err isa ArgumentError || rethrow()
            throw(ArgumentError("$(t.path): row $(r + 1), column '$name': $(err.msg)"))
        end
    end
    return out
end

"""
    numeric_column(t::CSVTable, j::Integer; allow_missing = false) -> Vector{Float64}

Numeric column by position (for files whose header names are not meaningful).
"""
numeric_column(t::CSVTable, j::Integer; allow_missing::Bool = false) =
    numeric_column(t, t.header[j]; allow_missing = allow_missing)

"""
    write_csv(path, header, columns)

Write columns (vectors of equal length) with a header line. Numbers are written with
`repr`, so they round-trip exactly.
"""
function write_csv(path::AbstractString, header::AbstractVector, columns::AbstractVector)
    length(header) == length(columns) || throw(ArgumentError("header and columns differ in length"))
    n = isempty(columns) ? 0 : length(first(columns))
    all(c -> length(c) == n, columns) || throw(ArgumentError("columns differ in length"))
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, join((_csvcell(h) for h in header), ","))
        for i in 1:n
            println(io, join((_csvcell(c[i]) for c in columns), ","))
        end
    end
    return path
end

_csvcell(x::AbstractFloat) = isnan(x) ? "NaN" : isinf(x) ? (x > 0 ? "Inf" : "-Inf") : repr(x)
_csvcell(x::Integer) = string(x)
_csvcell(x::Bool) = x ? "true" : "false"
function _csvcell(x)
    s = string(x)
    return occursin(r"[\",\n\r]", s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s
end
