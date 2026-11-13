import Testing

struct TodoMatchTests {
    @Test func matchesSameItemLoosely() {
        #expect(TodoMatch.answers("Best ramen", todo: "best ramen"))
        #expect(TodoMatch.answers("buy a SIM card.", todo: "Buy a SIM card"))
        #expect(TodoMatch.answers("Souvenirs for mom", todo: "souvenirs for mom and dad"))
    }

    @Test func ignoresGeneralAndOtherItems() {
        #expect(!TodoMatch.answers("general", todo: "Best ramen"))
        #expect(!TodoMatch.answers("Best ramen", todo: "Buy a SIM card"))
        #expect(!TodoMatch.answers("", todo: "Best ramen"))
    }
}
