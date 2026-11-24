import PDFKit
import XCTest
@testable import PaperAndGrain

final class PageNumberTests: XCTestCase {
    func testOverrideDisablesTemplateNumbersAndEnablesNumbersInClassicProjects() throws {
        let page = BookPage(layout: .text, text: "Partenza")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = directory.appendingPathComponent("proof.pdf")
        var book = Book(title: "Test", pages: [page], template: .atlas)

        func check(numbered: Bool) throws {
            XCTAssertEqual(PageComposition(page: page, book: book).folio != nil, numbered)
            let encoded = try JSONEncoder().encode(book)
            let reopened = try JSONDecoder().decode(Book.self, from: encoded)
            XCTAssertEqual(reopened.showPageNumbers, book.showPageNumbers)
            try BookPDF.write(reopened, directory: directory, to: pdf)
            let printed = try XCTUnwrap(PDFDocument(url: pdf)?.page(at: 0)?.string)
            XCTAssertTrue(printed.contains("Partenza"))
            XCTAssertEqual(printed.split(whereSeparator: \.isWhitespace).contains("1"), numbered)
        }

        try check(numbered: true)
        book.showPageNumbers = false
        try check(numbered: false)
        book.template = nil
        book.showPageNumbers = true
        try check(numbered: true)
    }
}
