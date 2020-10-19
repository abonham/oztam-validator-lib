import XCTest
@testable import OztamValidatorLib

final class oztam_validator_libTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
		guard case let .success(f) = try! Oztail(userName: "broadcaster", password:  "v5OjCKRI", debug: false).fetch("5061c2de-7c9d-def0-7812-ee0c67209596") else { return XCTFail() }
        XCTAssertEqual(f, true)
    }

    func testProd() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        guard case let .success(f) = try! Oztail(userName: "broadcaster", password:  "v5OjCKRI").fetch("5061c2de-7c9d-def0-7812-ee0c67209596") else { return XCTFail() }
        XCTAssertEqual(f, true)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
