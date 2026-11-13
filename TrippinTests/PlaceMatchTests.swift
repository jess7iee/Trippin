import Testing

struct PlaceMatchTests {
    @Test func rejectsUnrelatedNearbyResult() {
        // What a Tokyo-biased search returned for a Kunming street address.
        #expect(!PlaceMatch.isRelevant(query: "云南省昆明市西山区广福路与前兴路交叉口商鼎大厦1栋，650228",
                                      name: "Tachikawa Station North Entrance Bicycle Parking",
                                      address: "Tachikawa, Tokyo, Japan"))
        #expect(!PlaceMatch.isRelevant(query: "Lijiang Airport", name: "Ibaraki High School", address: "Ryugasaki, Ibaraki, Japan"))
    }

    @Test func acceptsMatchingNames() {
        #expect(PlaceMatch.isRelevant(query: "Fairfield by Marriott Kunming Xishan",
                                     name: "Fairfield by Marriott Kunming Xishan", address: "Kunming, Yunnan, China"))
        #expect(PlaceMatch.isRelevant(query: "San Francisco Airport",
                                     name: "San Francisco International Airport (SFO)", address: "San Francisco, CA"))
        #expect(PlaceMatch.isRelevant(query: "昆明西山万豪万枫酒店", name: "昆明西山万豪万枫酒店", address: nil))
    }

    @Test func oneSharedPinyinSyllableIsNotEnough() {
        #expect(!PlaceMatch.isRelevant(query: "Dong Lai Shun Wangfujing, Dongcheng District, Beijing",
                                      name: "Dong Gao Fang Hu Tong", address: "Dongcheng, Beijing, China"))
        #expect(!PlaceMatch.isRelevant(query: "Dong Lai Shun Wangfujing, Beijing",
                                      name: "Renaissance Beijing Wangfujing Hotel", address: "Beijing, China"))
        #expect(PlaceMatch.isRelevant(query: "Beijing Capital Airport",
                                     name: "Beijing Capital International Airport", address: "Shunyi, Beijing"))
    }

    @Test func genericWordsAloneDontCount() {
        #expect(!PlaceMatch.isRelevant(query: "StarrySea Hotel", name: "Hotel Sunroute", address: "Shinjuku, Tokyo"))
    }
}
