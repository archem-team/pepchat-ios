//
//  RevoltTests.swift
//  RevoltTests
//
//  Created by Paul on 17/03/2023.
//

import XCTest
@testable import Revolt
import Types

final class RevoltTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testMessageDecodesEveryoneFlagAndCombinesMentionSemantics() throws {
        let everyoneJSON = Data(#"{"_id":"01TESTMESSAGE0000000000000","content":"@everyone","author":"author","channel":"channel","flags":2}"#.utf8)
        let everyoneMessage = try JSONDecoder().decode(Types.Message.self, from: everyoneJSON)

        XCTAssertTrue(everyoneMessage.mentionsEveryone)
        XCTAssertTrue(everyoneMessage.mentionsUser("any-user"))

        let directJSON = Data(#"{"_id":"01TESTMESSAGE0000000000001","author":"author","channel":"channel","mentions":["target"]}"#.utf8)
        let directMessage = try JSONDecoder().decode(Types.Message.self, from: directJSON)

        XCTAssertFalse(directMessage.mentionsEveryone)
        XCTAssertTrue(directMessage.mentionsUser("target"))
        XCTAssertFalse(directMessage.mentionsUser("other"))
    }

    func testMentionEveryonePermissionSurvivesOverwriteApplication() {
        let granted = Types.Permissions.none.apply(
            overwrite: Overwrite(a: .mentionEveryone, d: .none)
        )
        XCTAssertTrue(granted.contains(.mentionEveryone))
        XCTAssertTrue(Types.Permissions.all.contains(.mentionEveryone))

        let denied = granted.apply(
            overwrite: Overwrite(a: .none, d: .mentionEveryone)
        )
        XCTAssertFalse(denied.contains(.mentionEveryone))
    }

    func testEveryoneSuggestionRequiresPermissionAndMatchingPrefix() {
        XCTAssertTrue(MentionInputUtilities.shouldIncludeEveryone(searchText: "", canMentionEveryone: true))
        XCTAssertTrue(MentionInputUtilities.shouldIncludeEveryone(searchText: "eve", canMentionEveryone: true))
        XCTAssertTrue(MentionInputUtilities.shouldIncludeEveryone(searchText: "EVERYONE", canMentionEveryone: true))
        XCTAssertFalse(MentionInputUtilities.shouldIncludeEveryone(searchText: "other", canMentionEveryone: true))
        XCTAssertFalse(MentionInputUtilities.shouldIncludeEveryone(searchText: "eve", canMentionEveryone: false))
    }

    func testReplacingActiveMentionIsCursorAndUTF16Safe() throws {
        let text = "😀 Hello @eve world"
        let cursor = NSRange(location: ("😀 Hello @eve" as NSString).length, length: 0)
        let replacement = try XCTUnwrap(MentionInputUtilities.replacingActiveMention(
            in: text,
            selectedRange: cursor,
            with: "@everyone "
        ))

        XCTAssertEqual(replacement.text, "😀 Hello @everyone world")
        XCTAssertEqual(
            replacement.selectedRange.location,
            ("😀 Hello @everyone " as NSString).length
        )
        XCTAssertEqual(
            MentionInputUtilities.searchText(in: "before @eve after", selectedRange: NSRange(location: 11, length: 0)),
            "eve"
        )
        XCTAssertNil(MentionInputUtilities.replacingActiveMention(
            in: text,
            selectedRange: NSRange(location: NSNotFound, length: 0),
            with: "@everyone "
        ))
    }

    func testEveryoneMentionRangesExcludeEscapesAndCode() {
        let text = "@everyone \\@everyone `@everyone` ```swift\n@everyone\n``` end @everyone"
        let ranges = MentionInputUtilities.everyoneMentionRanges(in: text)
        let nsText = text as NSString

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges.map { nsText.substring(with: $0) }, ["@everyone", "@everyone"])
    }

    func testUserMentionTokensResolveNumericAndULIDIdentifiers() {
        let text = "Hi <@1297812287981359106> and <@01TESTUSER000000000000000>"
        let resolved = text.replacingUserMentionTokens { userId in
            userId == "01TESTUSER000000000000000" ? "Akshat" : nil
        }

        XCTAssertEqual(resolved, "Hi @unknown-user and @Akshat")
        XCTAssertFalse(resolved.contains("<@"))
    }

    func testUserMentionFallbackNeverLeaksRawIdentifier() {
        let rawMention = "<@1297812287981359106>"
        XCTAssertEqual(
            rawMention.replacingUserMentionTokens { _ in nil },
            "@unknown-user"
        )
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
