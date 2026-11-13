@testset "CSV reader" begin
    lf = "a,b,c\n1,2,3\n4,\"x, y\",6\n"
    t = read_csv_table(tmpfile(lf))
    @test t.header == ["a", "b", "c"]
    @test length(t) == 2
    @test G.column(t, "b") == ["2", "x, y"]                 # quoted comma
    # BOM, CRLF and CR-only line endings, missing final newline: all identical
    bom = vcat(UInt8[0xef, 0xbb, 0xbf], Vector{UInt8}(lf))
    for content in (bom, replace(lf, "\n" => "\r\n"), replace(lf, "\n" => "\r"), chop(lf))
        t2 = read_csv_table(tmpfile(content))
        @test t2.header == t.header && t2.rows == t.rows
    end
    @test G.column(read_csv_table(tmpfile("a\n\"he said \"\"hi\"\"\"\n")), "a") == ["he said \"hi\""]
    # errors name the file and line
    @test_throws ArgumentError read_csv_table(tmpfile("a,b\n1,2,3\n"))
    @test_throws ArgumentError read_csv_table(tmpfile("a,a\n1,2\n"))
    @test_throws ArgumentError read_csv_table(tmpfile("a,b\n\"1,2\n"))
    @test_throws ArgumentError read_csv_table("this/file/does/not/exist.csv")
    tn = read_csv_table(tmpfile("x,y\n1.5,inf\n_inf,NA\n"))
    @test G.numeric_column(tn, "x"; allow_missing=true)[1] == 1.5
    @test G.numeric_column(tn, "y"; allow_missing=true)[1] == Inf
    @test isnan(G.numeric_column(tn, "y"; allow_missing=true)[2])
    @test G.parse_number("_inf") == -Inf
    @test_throws ArgumentError G.numeric_column(tn, "y")    # NA not allowed by default
    @test_throws ArgumentError G.numeric_column(tn, "z")    # missing column
    # write → read round trip keeps every bit
    vals = [0.1, 1 / 3, -2.5e-300, Inf, NaN]
    path = G.write_csv(tmpfile(""), ["v", "s"], [vals, ["a", "b,c", "d", "e", "f"]])
    back = read_csv_table(path)
    @test isequal(G.numeric_column(back, "v"; allow_missing=true), vals)
    @test G.column(back, "s")[2] == "b,c"
end
