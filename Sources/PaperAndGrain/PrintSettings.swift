import Foundation

struct PrintSettings: Codable, Hashable, Sendable {
    var bleedMM: Double = 3
    var safeMM: Double = 10
    var targetPPI: Double = 300
    var spreads = false
    var firstPageOnRight: Bool? = nil
    /// The print-service profile chosen in **Book & Print** (`PrintProfile.id`); nil is generic print.
    var profileID: String? = nil
    /// The product size (`PrintProfile.Size.id`); nil means the size that matches the book's trim.
    var profileSizeID: String? = nil
    /// The paper, for products whose spine depends on it; nil is the product's first paper.
    var profilePaperID: String? = nil
    /// Cover measures the author typed over the profile's values.
    var profileMeasures: PrintMeasures? = nil
}

struct BookCover: Codable, Hashable, Sendable {
    var title = ""
    var frontPhotoID: UUID?
    var backPhotoID: UUID?
    var spineMM: Double = 0
    var backText: String? = nil
    var typography: EditorialTypography? = nil
    var frontTitleFrame: PageRect? = nil
    var backTextFrame: PageRect? = nil
    var frontPhotoPlacement: PhotoPlacement? = nil
    var backPhotoPlacement: PhotoPlacement? = nil
}
