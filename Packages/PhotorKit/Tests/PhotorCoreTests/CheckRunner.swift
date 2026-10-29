import Foundation
import Darwin

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}
func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if !condition() { throw CheckFailure(description: "\(file):\(line): condizione non soddisfatta") }
}
func require<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure(description: "\(file):\(line): valore mancante") }
    return value
}

@main
struct CheckRunner {
    static func main() async {
        setbuf(stdout, nil)
        alarm(60)
        do {
            let checks = CoreTests()
            try checks.memoryReservationsSurviveOwnerRemovalAndReleaseOnce()
            print("PASS budget e durata delle prenotazioni")
            try checks.plannerBoundsDirectionAndRAWLimit()
            print("PASS priorità, bordi del catalogo e finestra RAW")
            try checks.evictionPreservesCurrentAndNearerPhotos()
            print("PASS eliminazione: foto corrente e vicine protette")
            try checks.catalogNaturalOrderAndOrientationAwareJPEGDecode()
            print("PASS catalogo, ordinamento naturale, EXIF, ridimensionamento e colore")
            try await PipelineTests().folderSwitchRejectsOldResultsAndLimitsWorkers()
            print("PASS cambio cartella durante la decodifica e limite di due worker")
            try await AlbumTests().persistenceMembershipAndLimits()
            print("PASS album: persistenza, limite, appartenenza, spostamento e salvataggi fuori ordine")
            try await FileTests().transferCollisionCancellationAndFailure()
            print("PASS file: copie integre, omonimi, spostamento parziale, annullamento e file modificati")
            try await ThumbnailTests().boundedWorkersAndCancellation()
            print("PASS miniature: due worker, cancellazione e rilascio della memoria")
            print("8 gruppi di verifiche superati")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
