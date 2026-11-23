import Foundation

struct PrintSettings: Codable, Hashable, Sendable {
    var bleedMM: Double = 3
    var safeMM: Double = 10
    var targetPPI: Double = 300
    var spreads = false
    var firstPageOnRight: Bool? = nil
}

struct BookCover: Codable, Hashable, Sendable {
    var title = ""
    var frontPhotoID: UUID?
    var backPhotoID: UUID?
    var spineMM: Double = 0
}
