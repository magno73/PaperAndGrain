import AppKit
import CoreText
import PDFKit
import XCTest
@testable import PaperAndGrain

final class TypographyTests: XCTestCase {
    func testLegacyDefaultsAndPersistedFieldWiseInheritance() throws {
        var book = Book(title: "Journal", pages: [BookPage(layout: .text)], template: .diary)
        let data = try JSONEncoder().encode(book)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("typography"))
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: data), book)
        book.typography = EditorialTypography(title: .init(fontName: "Menlo-Regular", pointSize: 32),
                                             body: .init(pointSize: 20, alignment: .right))
        book.pages[0].typography = EditorialTypography(title: .init(alignment: .center), body: .init(pointSize: 12))
        let box = PageTextBox(text: "Box", frame: .init(x: 0, y: 0, width: 1, height: 1),
                              typography: .init(alignment: .justified))
        book.pages[0].textBoxes = [box]
        book.cover = BookCover(typography: .init(title: .init(pointSize: 64)))
        XCTAssertEqual(book.titleStyle(for: book.pages[0]), .init(fontName: "Menlo-Regular", pointSize: 32, alignment: .center))
        XCTAssertEqual(book.bodyStyle(for: book.pages[0]), .init(pointSize: 12, alignment: .right))
        XCTAssertEqual(book.bodyStyle(for: box), .init(pointSize: 20, alignment: .justified))
        XCTAssertEqual(book.coverTextStyle(front: true), .init(fontName: "Menlo-Regular", pointSize: 64))
        XCTAssertEqual(book.coverTextStyle(front: false), book.typography?.body)
        XCTAssertEqual(try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book)), book)
    }

    func testTypesetterResolvesAttributesAndFallbacks() throws {
        let style = BookTemplate.atlas.style
        let string = style.typography("Body", heading: "Head", mixed: true,
                                      titleStyle: .init(fontName: "Menlo-Regular", pointSize: 31, alignment: .center),
                                      bodyStyle: .init(fontName: "Unavailable-PaperAndGrain", pointSize: 999, alignment: .right))
        func font(_ index: Int) -> CTFont {
            string.attribute(.init(kCTFontAttributeName as String), at: index, effectiveRange: nil) as! CTFont
        }
        XCTAssertEqual(CTFontCopyPostScriptName(font(0)) as String, "Menlo-Regular")
        XCTAssertEqual(CTFontGetSize(font(0)), 31)
        XCTAssertEqual(CTFontCopyPostScriptName(font(5)) as String, style.bodyFont)
        XCTAssertEqual(CTFontGetSize(font(5)), 120)
        XCTAssertEqual((string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .center)
        XCTAssertEqual((string.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .right)
        XCTAssertEqual(EditorialTextStyle(pointSize: -1).normalizedSize, 6)
        XCTAssertNil(EditorialTextStyle(pointSize: .nan).normalizedSize)
    }

    func testUnstyledPageUsesExactTemplateTypography() {
        let page = BookPage(layout: .mixed, text: "Body", heading: "Heading")
        for template in [nil] + BookTemplate.allCases.map(Optional.some) {
            let book = Book(title: "Journal", pages: [page], template: template)
            let expected = book.editorialStyle.typography(page.text, heading: page.heading, mixed: true)
            XCTAssertEqual(PageComposition.storyText(page: page, book: book), expected)
            XCTAssertTrue(EditorialTypesetter.fits(expected, in: CGRect(x: 20, y: 20, width: 300, height: 200)))
            XCTAssertFalse(EditorialTypesetter.fits(expected, in: CGRect(x: 20, y: 20, width: 300, height: 1)))
        }
    }

    func testAlignedTitleInPDFUsesEntireSafeWidth() throws {
        let page = BookPage(layout: .text, heading: "Editorial", typography: .init(title: .init(pointSize: 24, alignment: .right)))
        let book = Book(title: "Test", pages: [page], template: .diary)
        let composition = PageComposition(page: page, book: book)
        let rect = try XCTUnwrap(composition.story)
        XCTAssertEqual(rect.maxX, composition.bounds.maxX - book.contentInsetPoints, accuracy: 0.01)
        let folder = FileManager.default.temporaryDirectory
        let file = folder.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try BookPDF.write(book, directory: folder, to: file)
        let pdf = try XCTUnwrap(PDFDocument(url: file))
        let first = try XCTUnwrap(pdf.page(at: 0))
        let selection = try XCTUnwrap(pdf.findString("Editorial", withOptions: []).first)
        XCTAssertEqual(selection.bounds(for: first).maxX, rect.maxX, accuracy: 4)
    }

    func testStudioCoversAndStoryColumnsAcrossPageSizes() throws {
        let page = BookPage(layout: .text, text: "An observation about light.", heading: "Field notes")
        for template in [BookTemplate.swissGrid, .berlinQuarter, .japaneseInterval] {
            var book = Book(title: "Field notes", pages: [page], template: template)
            for (width, height) in [(148.0, 210.0), (300, 190), (210, 210)] {
                book.format.widthMM = width
                book.format.heightMM = height
                let face = BookCoverGeometry(book: book, front: true, bleed: 9)
                let title = try XCTUnwrap(face.titleFrame)
                let area = try XCTUnwrap(PageComposition(page: page, book: book).story)
                let panel = face.bounds.insetBy(dx: book.contentInsetPoints, dy: book.contentInsetPoints)
                XCTAssertTrue(face.bounds.contains(face.photoFrame))
                XCTAssertFalse(face.photoFrame.intersects(title))
                XCTAssertTrue(EditorialTypesetter.fits(face.title, in: title))
                XCTAssertEqual(area.width, panel.width * template.style.columnFraction, accuracy: 0.01)
                switch template {
                case .swissGrid:
                    XCTAssertNotNil(face.rule)
                    XCTAssertEqual(face.photoFrame.minX, panel.minX + panel.width / 3, accuracy: 0.01)
                case .berlinQuarter:
                    XCTAssertLessThan(face.photoFrame.maxY, title.minY)
                    XCTAssertEqual(face.photoFrame.width, panel.width, accuracy: 0.01)
                case .japaneseInterval:
                    XCTAssertLessThan(face.photoFrame.width * face.photoFrame.height, panel.width * panel.height / 3)
                    XCTAssertGreaterThan(area.minY, panel.minY + 0.18 * panel.height)
                default: XCTFail("Unexpected template")
                }
            }
        }
    }

    func testStudioMediumHeadlineFitsOneLineAndPreservesAuthoredTypography() throws {
        let headline = "Quando il deserto cambia colore"
        let page = BookPage(layout: .text, heading: headline)
        for template in [BookTemplate.swissGrid, .berlinQuarter, .japaneseInterval] {
            let book = Book(title: headline, pages: [page], template: template)
            let area = try XCTUnwrap(PageComposition(page: page, book: book).story)
            let style = template.style
            let chosen = style.fittedTitleStyle(headline, width: area.width, mixed: false, override: .init())
            let text = style.typography("", heading: headline, mixed: false, titleStyle: chosen)
            let setter = CTTypesetterCreateWithAttributedString(text)
            XCTAssertEqual(CTTypesetterSuggestLineBreak(setter, 0, area.width), text.length, template.rawValue)
            let explicit = EditorialTextStyle(fontName: "Georgia", pointSize: 48, alignment: .center)
            XCTAssertEqual(style.fittedTitleStyle(headline, width: area.width / 2, mixed: false, override: explicit), explicit)
            XCTAssertNil(style.fittedTitleStyle("Quando il deserto\ncambia colore", width: 160, mixed: false, override: .init()).pointSize)
            XCTAssertNil(style.fittedTitleStyle(String(repeating: "Distanza ", count: 9), width: 160, mixed: false, override: .init()).pointSize)
        }
    }

    func testCoverAccommodatesLargerTypeOnBothFaces() throws {
        var book = Book(title: "Cover", template: .essential)
        book.cover = BookCover(title: "A\nB", backText: "X\nY", typography: .init(title: .init(pointSize: 84), body: .init(pointSize: 84)))
        for front in [true, false] {
            let face = BookCoverGeometry(book: book, front: front)
            let text = try XCTUnwrap(face.titleFrame)
            XCTAssertFalse(text.intersects(face.photoFrame))
            XCTAssertGreaterThanOrEqual(text.height, EditorialTypesetter.requiredHeight(face.title, width: text.width) - 0.001)
        }
    }
}
