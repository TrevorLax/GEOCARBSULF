@testset "Aqua" begin
    Aqua.test_all(GeocarbPrecalibration; ambiguities=false)
    # ambiguities among this package's own methods only
    Aqua.test_ambiguities(GeocarbPrecalibration; recursive=false)
end
