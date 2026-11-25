import Foundation
import XCTest
@testable import PaperAndGrain

final class NavigatorPageGapTests: XCTestCase {
    func testGapsUseLogicalPagesIncludingAnIndivisibleSpread() {
        let first = BookPage()
        let spread = BookPage(layout: .fullSpread)
        let last = BookPage()
        let pages = [first, spread, last]

        XCTAssertEqual(NavigatorPageGap.before(first.id).index(in: pages), 0)
        XCTAssertEqual(NavigatorPageGap.before(spread.id).index(in: pages), 1)
        let following = NavigatorPageGap.before(last.id)
        XCTAssertEqual(following.index(in: pages), 2)
        XCTAssertEqual(following.dropTarget(in: pages)?.id, last.id)
        XCTAssertEqual(following.dropTarget(in: pages)?.after, false)
        XCTAssertNil(following.index(in: [first, spread]))
        XCTAssertNil(following.dropTarget(in: [first, spread]))

        XCTAssertEqual(NavigatorPageGap.end.index(in: pages), 3)
        XCTAssertEqual(NavigatorPageGap.end.dropTarget(in: pages)?.id, last.id)
        XCTAssertEqual(NavigatorPageGap.end.dropTarget(in: pages)?.after, true)
        XCTAssertEqual(NavigatorPageGap.end.index(in: []), 0)
        XCTAssertNil(NavigatorPageGap.end.dropTarget(in: []))
    }
}
