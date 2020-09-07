import XCTest
@testable import oztam_validator_lib

final class oztam_validator_libTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
		guard case let .success(f) = try! Oztail(userName: "broadcaster", password:  "v5OjCKRI").fetch("85D88FA3-F915-0B57-7AF1-2E72B9E1FC0E") else { return XCTFail() }
        XCTAssertEqual(f, true)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
