import Testing
import Foundation
import SwiftData
@testable import flyfun_forms

/// In-memory container built from the app's own model list, so a model added
/// to `AppSchema` is covered here without editing the test.
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: AppSchema.schema, configurations: config)
}

/// A scratch temp directory standing in for the app's temp directory, with
/// the forms root inside it.
private func makeScratchFiles() throws -> (tmp: URL, files: GeneratedFormFiles) {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalDataEraserTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    return (tmp, GeneratedFormFiles(root: tmp.appendingPathComponent("forms", isDirectory: true)))
}

@MainActor
private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
    try context.fetchCount(FetchDescriptor<T>())
}

@Suite("Delete All Data")
@MainActor
struct LocalDataEraserTests {

    @Test("Every model type in the schema is emptied, relationships and all")
    func erasesEveryModel() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pilot = Person(firstName: "Zed", lastName: "Zztest")
        let passenger = Person(firstName: "Ann", lastName: "Zzsample")
        context.insert(pilot)
        context.insert(passenger)
        let doc = TravelDocument(docType: "Passport", docNumber: "ZZ0000001", issuingCountry: "FRA")
        doc.person = passenger
        context.insert(doc)
        let aircraft = Aircraft()
        aircraft.registration = "ZZ-TST"
        context.insert(aircraft)
        let trip = Trip(name: "Test trip")
        context.insert(trip)
        let flight = Flight()
        flight.aircraft = aircraft
        flight.crew = [pilot]
        flight.passengers = [passenger]
        flight.responsiblePerson = pilot
        flight.trip = trip
        context.insert(flight)
        try context.save()

        let deleted = try LocalDataEraser.eraseAll(in: context, formFiles: try makeScratchFiles().files)

        #expect(deleted == 6)
        #expect(try count(Person.self, in: context) == 0)
        #expect(try count(TravelDocument.self, in: context) == 0)
        #expect(try count(Aircraft.self, in: context) == 0)
        #expect(try count(Flight.self, in: context) == 0)
        #expect(try count(Trip.self, in: context) == 0)
    }

    @Test("The deletion is saved, not just pending in the context")
    func erasureIsSaved() throws {
        let container = try makeTestContainer()
        container.mainContext.insert(Person(firstName: "Zed", lastName: "Zztest"))
        try container.mainContext.save()

        try LocalDataEraser.eraseAll(in: container.mainContext, formFiles: try makeScratchFiles().files)

        #expect(!container.mainContext.hasChanges)
        let other = ModelContext(container)
        #expect(try count(Person.self, in: other) == 0)
    }

    @Test("An empty store is a no-op")
    func emptyStore() throws {
        let container = try makeTestContainer()
        let deleted = try LocalDataEraser.eraseAll(in: container.mainContext, formFiles: try makeScratchFiles().files)
        #expect(deleted == 0)
    }

    @Test("Generated forms are deleted with the data")
    func erasesGeneratedForms() throws {
        let container = try makeTestContainer()
        let (tmp, files) = try makeScratchFiles()
        let form = try files.write(Data("filled".utf8), filename: "LFAC_customs.pdf")
        #expect(FileManager.default.fileExists(atPath: form.path))

        try LocalDataEraser.eraseAll(in: container.mainContext, formFiles: files)

        #expect(!FileManager.default.fileExists(atPath: form.path))
        try? FileManager.default.removeItem(at: tmp)
    }
}

@Suite("Generated form files")
struct GeneratedFormFilesTests {

    @Test("A form keeps the server's filename, in a directory of its own")
    func writeKeepsFilename() throws {
        let (tmp, files) = try makeScratchFiles()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let first = try files.write(Data("a".utf8), filename: "LFAC_customs.pdf")
        let second = try files.write(Data("b".utf8), filename: "LFAC_customs.pdf")

        #expect(first.lastPathComponent == "LFAC_customs.pdf")
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("a".utf8))
        #expect(first.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                == files.root.standardizedFileURL)
    }

    @Test("A filename cannot place the form outside its directory")
    func writeRejectsPaths() throws {
        let (tmp, files) = try makeScratchFiles()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let slashed = try files.write(Data("a".utf8), filename: "../escape.pdf")
        #expect(slashed.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
                == files.root.standardizedFileURL)
        let dots = try files.write(Data("a".utf8), filename: "..")
        #expect(dots.lastPathComponent == "form")
    }

    @Test("Removing a form deletes it with its directory, and nothing outside the root")
    func removeIsScoped() throws {
        let (tmp, files) = try makeScratchFiles()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let form = try files.write(Data("a".utf8), filename: "form.pdf")
        let keep = try files.write(Data("b".utf8), filename: "other.pdf")
        let outside = tmp.appendingPathComponent("sub/unrelated.pdf")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("c".utf8).write(to: outside)

        files.remove(form)
        files.remove(outside)

        #expect(!FileManager.default.fileExists(atPath: form.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("The sweep deletes only forms older than the grace period")
    func sweepByAge() throws {
        let (tmp, files) = try makeScratchFiles()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let old = try files.write(Data("a".utf8), filename: "old.pdf")
        let fresh = try files.write(Data("b".utf8), filename: "fresh.pdf")

        // Both just written: inside the grace period.
        files.sweep(olderThan: 30 * 60)
        #expect(FileManager.default.fileExists(atPath: old.path))
        try FileManager.default.setAttributes(
            [.creationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: old.deletingLastPathComponent().path
        )
        files.sweep(olderThan: 30 * 60)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test("Remove all clears the root and forms an older build left in tmp, nothing else")
    func removeAllIncludesLegacy() throws {
        let (tmp, files) = try makeScratchFiles()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let form = try files.write(Data("a".utf8), filename: "form.pdf")
        let legacy = tmp.appendingPathComponent("EGTF_gar.xlsx")
        try Data("b".utf8).write(to: legacy)
        let unrelated = tmp.appendingPathComponent("cache.json")
        try Data("c".utf8).write(to: unrelated)

        files.removeAll()

        #expect(!FileManager.default.fileExists(atPath: form.path))
        #expect(!FileManager.default.fileExists(atPath: files.root.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
