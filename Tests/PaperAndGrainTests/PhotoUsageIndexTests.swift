import XCTest
@testable import PaperAndGrain

final class PhotoUsageIndexTests: XCTestCase {
    func testUsageFollowsVisibleCompositionCoverAndPageOrder() {
        let landscape = BookPhoto(name: "Landscape", filename: "landscape.jpg", pixelWidth: 1600, pixelHeight: 800)
        let portrait = BookPhoto(name: "Portrait", filename: "portrait.jpg", pixelWidth: 800, pixelHeight: 1600)
        let unused = BookPhoto(name: "Unused", filename: "unused.jpg", pixelWidth: 1000, pixelHeight: 1000)
        let opening = BookPage(layout: .fullPage, photoIDs: [portrait.id, unused.id])
        let spread = BookPage(layout: .fullSpread, photoIDs: [landscape.id])
        let repeated = BookPage(photoIDs: [landscape.id])
        var book = Book(title: "Test", photos: [landscape, portrait, unused], pages: [opening, spread, repeated],
                        cover: BookCover(frontPhotoID: landscape.id, backPhotoID: portrait.id))

        let index = PhotoUsageIndex()
        let usage = index.locations(in: book)
        XCTAssertEqual(usage[landscape.id], [.page(2...3), .page(4...4), .frontCover])
        XCTAssertEqual(usage[portrait.id], [.page(1...1), .backCover])
        XCTAssertNil(usage[unused.id])
        XCTAssertEqual(index.locations(in: book), usage)

        book.pages.swapAt(0, 1)
        book.cover?.frontPhotoID = nil
        let reordered = index.locations(in: book)
        XCTAssertEqual(reordered[landscape.id], [.page(1...2), .page(4...4)])
        XCTAssertEqual(reordered[portrait.id], [.page(3...3), .backCover])
    }
}
