import Foundation
import XCTest
@testable import PaperAndGrain

final class PhotoLibraryOrderingTests: XCTestCase {
    private let locale = Locale(identifier: "it")

    func testChronologicalOrderHoldsWithinDayAndLeavesUndatedPhotosLast() {
        let library = PhotoLibraryOrdering()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let early = photo("early", daySeconds: 60)
        let late = photo("late", daySeconds: 120)
        let next = photo("next", daySeconds: 86_400)
        let sameTime = photo("sameTime", daySeconds: 60)
        let undated = photo("undated")

        let groups = library.groups(for: [undated, next, sameTime, late, early], order: .date,
                                    locale: locale, calendar: calendar)
        XCTAssertEqual(groups.map(\.id), [.day(Date(timeIntervalSince1970: 0)),
                                          .day(Date(timeIntervalSince1970: 86_400)), .unknown])
        XCTAssertEqual(groups.map { $0.photos.map(\.name) }, [["sameTime", "early", "late"], ["next"], ["undated"]])
    }

    func testPlaceUsesOfflineNamesAndGroupsNearbyCoordinates() {
        var city = photo("City")
        city.location = PhotoLocation(name: "Windhoek")
        var first = photo("Camp", daySeconds: 120)
        first.location = PhotoLocation(latitude: -19.1751, longitude: 15.918)
        let second = photo("Park", daySeconds: 60)
        let missing = photo("Unknown")
        let locations = [second.id: PhotoLocation(latitude: -19.176, longitude: 15.924)]
        let groups = PhotoLibraryOrdering().groups(for: [first, missing, second, city], order: .place,
                                                   locale: locale, places: locations)
        XCTAssertEqual(groups.map(\.id), [.place("Windhoek"), .area(latitude: -384, longitude: 318), .unknown])
        XCTAssertEqual(groups.map { $0.photos.map(\.name) }, [["City"], ["Park", "Camp"], ["Unknown"]])
    }

    func testSubjectAndUsageUpdateWhenPhotoOrAssignmentsChange() {
        var person = photo("Person")
        person.analysis = PhotoAnalysis(labels: ["portrait"], concepts: ["people"])
        var desert = photo("Desert")
        desert.analysis = PhotoAnalysis(labels: ["dune"], concepts: ["sand", "outdoors", "desert"])
        let extra = photo("Other")
        let ordering = PhotoLibraryOrdering()
        let photos = [person, extra, desert]

        XCTAssertEqual(ordering.groups(for: photos, order: .subject, locale: locale).map(\.id),
                       [.subject("desert"), .subject("people"), .unknown])
        let used = ordering.groups(for: photos, order: .usage, locale: locale, used: [person.id])
        XCTAssertEqual(used.map(\.id), [.unused, .used])
        XCTAssertEqual(used.first?.photos.map(\.name), ["Other", "Desert"])
        let updated = ordering.groups(for: photos, order: .usage, locale: locale, used: [person.id, extra.id])
        XCTAssertEqual(updated.first?.photos.map(\.name), ["Desert"])
    }

    private func photo(_ name: String, daySeconds: Double? = nil) -> BookPhoto {
        BookPhoto(name: name, capturedAt: daySeconds.map(Date.init(timeIntervalSince1970:)),
                  filename: name + ".jpg", pixelWidth: 100, pixelHeight: 100)
    }
}
