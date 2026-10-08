import Testing
@testable import flyfun_forms

@Suite("AirportRegion")
struct AirportRegionTests {

    @Test("Slovakia (LZ) is Schengen")
    func slovakia() {
        #expect(AirportRegion.region(for: "LZIB") == .schengen)
    }

    @Test("Cyprus (LC) and Ireland (EI) are EU but not Schengen")
    func euNonSchengen() {
        #expect(AirportRegion.region(for: "LCLK") == .euNonSchengen)
        #expect(AirportRegion.region(for: "EIDW") == .euNonSchengen)
    }

    @Test("the Canary Islands (GC) are Schengen")
    func canaries() {
        #expect(AirportRegion.region(for: "GCLP") == .schengen)
    }

    @Test("Luxembourg (EL) is Schengen")
    func luxembourg() {
        #expect(AirportRegion.region(for: "ELLX") == .schengen)
    }

    @Test("Svalbard and the Faroe Islands override their country's prefix")
    func exactOverrides() {
        #expect(AirportRegion.region(for: "ENSB") == .other)
        #expect(AirportRegion.region(for: "EKVG") == .other)
        // The rest of Norway and Denmark stay Schengen.
        #expect(AirportRegion.region(for: "ENGM") == .schengen)
        #expect(AirportRegion.region(for: "EKCH") == .schengen)
    }

    @Test("the Channel Islands and the Isle of Man count as UK")
    func crownDependencies() {
        #expect(AirportRegion.region(for: "EGJJ") == .uk)
        #expect(AirportRegion.region(for: "EGNS") == .uk)
    }

    @Test("Gibraltar (LX) and unknown prefixes are other")
    func otherRegions() {
        #expect(AirportRegion.region(for: "LXGB") == .other)
        #expect(AirportRegion.region(for: "KJFK") == .other)
        #expect(AirportRegion.region(for: "") == .other)
    }

    @Test("lookup ignores case and surrounding spaces")
    func normalisesInput() {
        #expect(AirportRegion.region(for: "lfac") == .schengen)
        #expect(AirportRegion.region(for: " ensb ") == .other)
    }
}
