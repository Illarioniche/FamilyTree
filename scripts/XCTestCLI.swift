// Compatibility for the synchronous XCTest subset used by this repository.
// Only check-core.sh compiles this file. Standard swift test uses real XCTest.
@_exported import Foundation

open class XCTestCase {
    public init() {}
    open func setUpWithError() throws {}
    open func setUp() {}
    open func tearDown() {}
    open func tearDownWithError() throws {}
}

private enum RecordedFailure: Error { case unwrap }

public enum CLIHarness {
    public private(set) static var tests = 0
    public private(set) static var assertions = 0
    public private(set) static var failures = 0
    public private(set) static var failedTests = 0
    private static var currentTest = ""

    fileprivate static func assertion() { assertions += 1 }
    fileprivate static func fail(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        failures += 1
        FileHandle.standardError.write(Data("\(file):\(line): error: \(currentTest): \(text)\n".utf8))
    }
    private static func unexpected(_ error: Error, phase: String) {
        // XCTUnwrap already recorded its failure before aborting the test method.
        guard !(error is RecordedFailure) else { return }
        fail("\(phase) threw unexpectedly: \(error)")
    }

    public static func run<T: XCTestCase>(_ name: String, make: () -> T, body: (T) throws -> Void) {
        tests += 1
        currentTest = name
        let initialFailures = failures
        let test = make()
        var setupSucceeded = false
        do { try test.setUpWithError(); test.setUp(); setupSucceeded = true }
        catch { unexpected(error, phase: "setUp") }
        if setupSucceeded {
            do { try body(test) }
            catch { unexpected(error, phase: "Test") }
        }
        test.tearDown()
        do { try test.tearDownWithError() }
        catch { unexpected(error, phase: "tearDown") }
        if failures == initialFailures { print("PASS \(name)") }
        else { failedTests += 1; print("FAIL \(name)") }
    }

    public static func finish() -> Int32 {
        print("\n\(tests) tests, \(assertions) assertions, \(failedTests) failed tests, \(failures) failures.")
        return failures == 0 && tests > 0 && assertions > 0 ? 0 : 1
    }

    /// A separate subprocess runs this before the repository suite. Expected
    /// failures must be counted and must produce exit 1; any mismatch exits 2.
    public static func verifyHarness() -> Int32 {
        enum Marker: Error { case expected }
        func throwing() throws -> Int { throw Marker.expected }
        run("harness.passing", make: { XCTestCase() }) { _ in
            XCTAssertEqual(2, 2)
            XCTAssertTrue(true)
            XCTAssertFalse(false)
            XCTAssertGreaterThan(2, 1)
            XCTAssertGreaterThanOrEqual(2, 2)
            XCTAssertLessThanOrEqual(2, 2)
            XCTAssertNotNil(2 as Int?)
            XCTAssertNoThrow(2)
            XCTAssertThrowsError(try throwing())
            _ = try XCTUnwrap(2 as Int?)
        }
        run("harness.failingAssertions", make: { XCTestCase() }) { _ in
            XCTAssertEqual(1, 2)
            XCTAssertTrue(false)
            XCTAssertFalse(true)
            XCTAssertGreaterThan(1, 2)
            XCTAssertGreaterThanOrEqual(1, 2)
            XCTAssertLessThanOrEqual(2, 1)
            XCTAssertNotNil(nil as Int?)
            XCTAssertNoThrow(try throwing())
            XCTAssertThrowsError(2)
            XCTAssertEqual(try throwing(), 2)
            XCTAssertThrowsError(try throwing()) { _ in XCTAssertTrue(false) }
        }
        run("harness.unwrap", make: { XCTestCase() }) { _ in _ = try XCTUnwrap(nil as Int?) }
        run("harness.thrownTest", make: { XCTestCase() }) { _ in throw Marker.expected }
        final class BadSetup: XCTestCase {
            override func setUpWithError() throws { throw NSError(domain: "ExpectedSetupFailure", code: 1) }
        }
        final class BadTeardown: XCTestCase {
            override func tearDownWithError() throws { throw NSError(domain: "ExpectedTeardownFailure", code: 1) }
        }
        run("harness.setup", make: { BadSetup() }) { _ in XCTFail("The body must not run after failed setup") }
        run("harness.teardown", make: { BadTeardown() }) { _ in }
        guard tests == 6, assertions == 23, failedTests == 5, failures == 15 else {
            print("Harness self-check mismatch: tests=\(tests), assertions=\(assertions), failedTests=\(failedTests), failures=\(failures)")
            return 2
        }
        print("Harness self-check verified")
        return finish()
    }
}

private func check(_ condition: () throws -> Bool, _ label: String, _ message: () -> String, file: StaticString, line: UInt) {
    CLIHarness.assertion()
    do {
        if try !condition() { CLIHarness.fail(label + suffix(message()), file: file, line: line) }
    } catch {
        CLIHarness.fail("\(label): expression threw \(error)" + suffix(message()), file: file, line: line)
    }
}
private func suffix(_ message: String) -> String { message.isEmpty ? "" : " — " + message }

public func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check({ try lhs() == rhs() }, "XCTAssertEqual failed", message, file: file, line: line)
}
public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check(expression, "XCTAssertTrue failed", message, file: file, line: line)
}
public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check({ try !expression() }, "XCTAssertFalse failed", message, file: file, line: line)
}
public func XCTAssertGreaterThan<T: Comparable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check({ try lhs() > rhs() }, "XCTAssertGreaterThan failed", message, file: file, line: line)
}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check({ try lhs() >= rhs() }, "XCTAssertGreaterThanOrEqual failed", message, file: file, line: line)
}
public func XCTAssertLessThanOrEqual<T: Comparable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check({ try lhs() <= rhs() }, "XCTAssertLessThanOrEqual failed", message, file: file, line: line)
}
public func XCTAssertNotNil<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    check({ try expression() != nil }, "XCTAssertNotNil failed", message, file: file, line: line)
}
public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CLIHarness.assertion()
    do { _ = try expression() }
    catch { CLIHarness.fail("XCTAssertNoThrow: \(error)" + suffix(message()), file: file, line: line) }
}
public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (Error) -> Void = { _ in }) {
    CLIHarness.assertion()
    do { _ = try expression() }
    catch { errorHandler(error); return }
    CLIHarness.fail("XCTAssertThrowsError: expression did not throw" + suffix(message()), file: file, line: line)
}
public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    CLIHarness.assertion()
    let value: T?
    do { value = try expression() }
    catch {
        CLIHarness.fail("XCTUnwrap: expression threw \(error)" + suffix(message()), file: file, line: line)
        throw RecordedFailure.unwrap
    }
    guard let value else {
        CLIHarness.fail("XCTUnwrap: value is nil" + suffix(message()), file: file, line: line)
        throw RecordedFailure.unwrap
    }
    return value
}
public func XCTFail(_ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    CLIHarness.assertion()
    CLIHarness.fail("XCTFail" + suffix(message()), file: file, line: line)
}
