import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(oztam_validator_libTests.allTests),
    ]
}
#endif
