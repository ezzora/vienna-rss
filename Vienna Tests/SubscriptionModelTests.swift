//
//  SubscriptionModelTests.swift
//  Vienna Tests
//
//  Copyright 2019
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest

class SubscriptionModelTests: XCTestCase {
    var subscriptionModel: SubscriptionModel?

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        self.subscriptionModel = SubscriptionModel()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        self.subscriptionModel = nil
        super.tearDown()
    }

    func testVerificationOfCompleteFileURLs() {
        // Test that when passed a complete file URL, the verification doesn't change the original
        guard
            let subscriptionModel = subscriptionModel,
            let unverifiedURL = URL(string: "file:///Users/test/test.xml"),
            let expectedURL = URL(string: "file:///Users/test/test.xml") else {
                XCTAssert(false, "Couldn't setup variables to perform test")
                return
        }

        XCTAssertEqual(expectedURL, subscriptionModel.verifiedFeedURL(from: unverifiedURL))
    }

    func testVerificationOfCompleteWebURLs() {
        // Test that then passed a complete web URL to an rss feed, the verification doesn't change the original
        guard
            let subscriptionModel = subscriptionModel,
            let unverifiedURL = URL(string: "http://www.abc.net.au/news/feed/51120/rss.xml"),
            let expectedURL = URL(string: "http://www.abc.net.au/news/feed/51120/rss.xml") else {
                XCTAssert(false, "Couldn't setup variables to perform test")
                return
        }

        XCTAssertEqual(expectedURL, subscriptionModel.verifiedFeedURL(from: unverifiedURL))
    }

    func testVerificationOfIncompleteWebURLs() {
        // Test that when passed a URL without an rss feed in the path component and without a scheme
        // that the returned URL is correct
        guard
            let subscriptionModel = subscriptionModel,
            let unverifiedURL = URL(string: "abc.net.au/news"),
            let expectedURL = URL(string: "http://abc.net.au/news/feed/51120/rss.xml") else {
                XCTAssert(false, "Couldn't setup variables to perform test")
                return
        }

        let verifiedURL = subscriptionModel.verifiedFeedURL(from: unverifiedURL)


        XCTAssertTrue((expectedURL as NSURL).isEquivalent(verifiedURL!))
    }

    func testVerificationOfHostRelativeWebURLs() {
        // Test that when passed a URL without an rss feed in the path component and without a scheme
        // that the returned URL is correct
        guard let subscriptionModel = subscriptionModel else {
            XCTAssert(false, "Couldn't setup variables to perform test")
            return
        }

        // Test 1

        guard
            let unverifiedURL_1 = URL(string: "https://news.ycombinator.com/news"),
            let expectedURL_1 = URL(string: "https://news.ycombinator.com/rss") else {
                XCTAssert(false, "Couldn't setup variables to perform test")
                return
        }

        let verifiedURL_1 = subscriptionModel.verifiedFeedURL(from: unverifiedURL_1)

        XCTAssertTrue((expectedURL_1 as NSURL).isEquivalent(verifiedURL_1))

        // Test 2

        // Reported by @cdevroe from https://twitter.com/cdevroe/status/517764086478958593
        guard
            let unverifiedURL_2 = URL(string: "https://adactio.com/journal/"),
            let expectedURL_2 = URL(string: "https://adactio.com/journal/rss") else {
                XCTAssert(false, "Couldn't setup variables to perform test")
                return
        }

        let verifiedURL_2 = subscriptionModel.verifiedFeedURL(from: unverifiedURL_2)

        XCTAssertTrue((expectedURL_2 as NSURL).isEquivalent(verifiedURL_2))

        // Test 3

        // Reported by @cdevroe from from https://twitter.com/cdevroe/status/517764395183915009
        guard
            let unverifiedURL_3 = URL(string: "shawnblanc.net"),
            let expectedURL_3 = URL(string: "http://shawnblanc.net/feed/") else {
                XCTAssert(false, "Couldn't setup variables to perform test")
                return
        }

        let verifiedURL_3 = subscriptionModel.verifiedFeedURL(from: unverifiedURL_3)

        XCTAssertTrue((expectedURL_3 as NSURL).isEquivalent(verifiedURL_3))
    }

}
