import XCTest
@testable import MustardKit

final class NotchScreenPickerTests: XCTestCase {
    func test_choose_prefersExternalOverNotch_whenBothConnected() {
        let notch = NotchScreenDescriptor(id: "built-in", hasNotch: true, isMain: false)
        let external = NotchScreenDescriptor(id: "external", hasNotch: false, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [notch, external]), external)
    }

    func test_choose_fallsBackToNotchScreen_whenItsTheOnlyDisplay() {
        let notch = NotchScreenDescriptor(id: "built-in", hasNotch: true, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [notch]), notch)
    }

    func test_choose_fallsBackToMain_whenNoNotchAndNoExternal() {
        let onlyScreen = NotchScreenDescriptor(id: "single", hasNotch: false, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [onlyScreen]), onlyScreen)
    }

    func test_choose_returnsNil_whenNoScreens() {
        XCTAssertNil(NotchScreenPicker.choose(from: []))
    }

    func test_choose_multipleExternals_picksFirstNonNotch() {
        let notch = NotchScreenDescriptor(id: "built-in", hasNotch: true, isMain: false)
        let externalA = NotchScreenDescriptor(id: "a", hasNotch: false, isMain: false)
        let externalB = NotchScreenDescriptor(id: "b", hasNotch: false, isMain: true)
        XCTAssertEqual(NotchScreenPicker.choose(from: [notch, externalA, externalB]), externalA)
    }
}
