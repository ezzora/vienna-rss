//
//  CriteriaTests.swift
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

class CriteriaTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

class CriteriaTreeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testCriteriaTreeInitWithString() {
        // This tests initialising a CriteriaTree with a string.
        // Only called by the Database class when loading smart folders
        let criteriaTreeString = "<?xml version=\"1.0\" encoding=\"utf-8\"?><criteriagroup condition=\"all\"><criteria field=\"Flagged\"><operator>1</operator><value>Yes</value></criteria></criteriagroup>"

        let testCriteriaTree = CriteriaTree(string: criteriaTreeString)

        guard let firstObject = testCriteriaTree?.criteriaEnumerator.allObjects.first else {
            XCTAssert(false, "Couldn't setup variables to perform test")
            return
        }

        guard let firstCriteria = firstObject as? Criteria else {
            XCTAssert(false, "Couldn't setup variables to perform test")
            return
        }

        XCTAssertEqual(firstCriteria.field, "Flagged")
        XCTAssertEqual(firstCriteria.operator, CriteriaOperator(rawValue: 1))
        XCTAssertEqual(firstCriteria.value, "Yes")
    }

    func testCriteriaTreeInitWithString2() {
        // This tests initialising a CriteriaTree with a string that has
        // multiple criteria.
        // Only called by the Database class when loading smart folders
        let criteriaTreeString = "<?xml version=\"1.0\" encoding=\"utf-8\"?><criteriagroup condition=\"all\"><criteria field=\"Flagged\"><operator>1</operator><value>Yes</value></criteria><criteria field=\"Date\"><operator>1</operator><value>today</value></criteria></criteriagroup>"

        let testCriteriaTree = CriteriaTree(string: criteriaTreeString)

        guard let allObjects = testCriteriaTree?.criteriaEnumerator.allObjects as? [Criteria] else {
            XCTAssert(false, "Couldn't setup variables to perform test")
            return
        }

        XCTAssertEqual(allObjects.count, 2)
    }

    func testCriteriaTreeString() {
        // This tests returning a criteria tree as an XML string
        let criteriaTreeString = "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?><criteriagroup condition=\"all\"><criteria field=\"Flagged\"><operator>1</operator><value>Yes</value></criteria></criteriagroup>"

        guard let testCriteriaTree = CriteriaTree(string: criteriaTreeString) else {
            XCTAssert(false, "Couldn't setup variables to perform test")
            return
        }

        XCTAssertEqual(testCriteriaTree.string.lowercased(), criteriaTreeString.lowercased())
    }

}
