import Testing
import Foundation

struct PlacesImportTests {
    private let list = """
    Here's your list:

    ```json
    {"trippinPlaces": 1, "places": [
      {"date": "2027-03-08", "time": "7:30 PM", "name": "Sample Hot Pot", "localName": "示例火锅",
       "address": "示例市示例区1号", "latitude": 39.9, "longitude": 116.4, "category": "food",
       "note": "Book ahead", "searchQuery": "Sample Hot Pot Beijing"},
      {"date": "2027-03-09", "name": "Sample Park", "latitude": 0, "longitude": 0},
      {"date": "not a date", "name": "Skipped"},
      {"date": "2027-03-09", "name": "  "}
    ]}
    ```
    """

    @Test func readsPlacesFromFencedJSONWithChatAround() throws {
        let places = try PlacesImport.parse(list)
        #expect(places.map(\.name) == ["Sample Hot Pot", "Sample Park"])
        let first = places[0]
        #expect(first.localName == "示例火锅")
        #expect(first.time == DateComponents(hour: 19, minute: 30))
        #expect(first.latitude == 39.9 && first.longitude == 116.4)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: first.date)
        #expect([c.year, c.month, c.day] == [2027, 3, 8])
    }

    @Test func dropsZeroCoordinates() throws {
        let park = try PlacesImport.parse(list)[1]
        #expect(park.latitude == nil && park.longitude == nil)
        #expect(park.time == nil)
    }

    @Test func rejectsOtherText() {
        #expect(throws: PlacesImport.ImportError.notAPlacesList) { try PlacesImport.parse("Flight UA888 SFO → PEK") }
        #expect(throws: PlacesImport.ImportError.noPlaces) { try PlacesImport.parse(#"{"places": [{"name": "No date"}]}"#) }
    }
}
