import XCTest

@testable import VolantCore

/// The `clipboard-write` permission and a row's `copy`: who may declare it, how sanitizing keeps or drops
/// it, and the checks downloaded SVG, text and image bytes must pass before Volant copies them.
final class ExtensionItemCopyTests: XCTestCase {
    private let hosts: Set<String> = ["assets.example.com"]

    private func manifest(output: String? = "items", permissions: [String]? = ["clipboard-write"]) -> ExtensionManifest {
        ExtensionManifest(id: "community.fictional.logos", name: "Fictional Logos", version: "1", module: "logos.wasm", capabilities: [],
                          sha256: String(repeating: "a", count: 64), hosts: output == "items" ? ["assets.example.com"] : nil, output: output,
                          permissions: permissions)
    }

    private func row(_ copy: String, permitted: Bool = true) throws -> ExtensionItem? {
        let output = #"{"items":[{"title":"Fictional logo","copy":"# + copy + "}]}"
        return try ExtensionNetwork.items(from: output, copyHosts: permitted ? hosts : nil).first
    }

    func testOnlyListExtensionsMayDeclareClipboardWrite() {
        XCTAssertNoThrow(try manifest().validate())
        XCTAssertTrue(manifest().wantsClipboardWrite)
        XCTAssertThrowsError(try manifest(output: nil).validate(), "A text extension has no rows to copy from")
        var json = manifest(output: nil); json.input = "json"
        XCTAssertThrowsError(try json.validate(), "JSON text extensions have no rows either")
        XCTAssertEqual(manifest().rowCopyHosts, hosts)
        XCTAssertNil(manifest(permissions: ["clipboard"]).rowCopyHosts)
    }

    func testClipboardWriteNeedsApprovalAgainOnUpdate() {
        let old = manifest(permissions: nil)
        XCTAssertFalse(manifest().requestsNoMoreThan(old), "Copying to the clipboard is new access")
        XCTAssertTrue(old.requestsNoMoreThan(manifest()))
        XCTAssertTrue(manifest().requestsNoMoreThan(manifest()))
    }

    func testCopyIsDroppedWithoutThePermission() throws {
        XCTAssertNil(try row(#"{"text":"<svg/>"}"#, permitted: false)?.copy)
        XCTAssertEqual(try row(#"{"text":"<svg/>"}"#)?.copy, ExtensionItemCopy(text: "<svg/>"))
        let reply = try ExtensionNetwork.reply(from: #"{"items":[{"title":"Logo","copy":{"text":"x"}}]}"#)
        XCTAssertNil(reply.items?.first?.copy, "A reply sanitized without copy hosts drops the copy")
    }

    func testTextCopiesAreBoundedAndNonEmpty() throws {
        let limit = String(repeating: "a", count: ExtensionItemCopy.maximumTextBytes)
        XCTAssertEqual(try row(#"{"text":"\#(limit)"}"#)?.copy?.text?.utf8.count, ExtensionItemCopy.maximumTextBytes)
        XCTAssertNil(try row(#"{"text":"\#(limit)a"}"#)?.copy, "Text over 64 KB is dropped, never cut")
        let multibyte = String(repeating: "é", count: ExtensionItemCopy.maximumTextBytes / 2 + 1)
        XCTAssertNil(try row(#"{"text":"\#(multibyte)"}"#)?.copy, "The limit counts UTF-8 bytes")
        XCTAssertNil(try row(#"{"text":""}"#)?.copy)
        XCTAssertNil(try row(#"{"text":"x","url":"https://assets.example.com/a.svg","type":"svg"}"#)?.copy, "A copy is text or a URL, not both")
        XCTAssertNil(try row("{}")?.copy)
    }

    func testURLCopiesNeedADeclaredHostAndAKnownType() throws {
        for type in ExtensionItemCopy.Kind.allCases.map(\.rawValue) {
            XCTAssertEqual(try row(#"{"url":"https://assets.example.com/logo","type":"\#(type)"}"#)?.copy?.kind?.rawValue, type)
        }
        XCTAssertNil(try row(#"{"url":"https://assets.example.com/logo.gif","type":"gif"}"#)?.copy)
        XCTAssertNil(try row(#"{"url":"https://assets.example.com/logo.svg"}"#)?.copy, "A URL copy needs a type")
        XCTAssertNil(try row(#"{"url":"https://other.example.com/logo.svg","type":"svg"}"#)?.copy, "Undeclared host")
        XCTAssertNil(try row(#"{"url":"http://assets.example.com/logo.svg","type":"svg"}"#)?.copy, "Plain http")
        XCTAssertNil(try row(#"{"url":"https://assets.example.com:8443/logo.svg","type":"svg"}"#)?.copy, "Another port")
        XCTAssertNil(try row(#"{"url":"https://user@assets.example.com/logo.svg","type":"svg"}"#)?.copy, "Credentials")
        XCTAssertNil(try row(#"{"url":"file:///etc/hosts","type":"text"}"#)?.copy)
    }

    func testTitlesAreOneLineOfFortyCharacters() throws {
        XCTAssertEqual(try row(#"{"text":"x","title":"  Copy SVG  "}"#)?.copy?.title, "Copy SVG")
        XCTAssertEqual(try row(#"{"text":"x","title":"Copy\nSVG"}"#)?.copy?.title, "Copy SVG")
        XCTAssertEqual(try row(#"{"text":"x","title":"\#(String(repeating: "b", count: 60))"}"#)?.copy?.title?.count, 40)
        let untitled = try XCTUnwrap(try row(#"{"text":"x","title":"   "}"#)?.copy)
        XCTAssertNil(untitled.title)
        XCTAssertEqual(untitled.displayTitle, "Copy")
    }

    func testConfirmationsNameWhatWasCopied() {
        XCTAssertEqual(ExtensionItemCopy(text: "x", title: "Copy SVG").confirmation, "Copied SVG")
        XCTAssertEqual(ExtensionItemCopy(url: "https://assets.example.com/a", type: "svg").confirmation, "Copied SVG")
        XCTAssertEqual(ExtensionItemCopy(url: "https://assets.example.com/a", type: "png", title: "Logo").confirmation, "Copied image")
        XCTAssertEqual(ExtensionItemCopy(text: "x").confirmation, "Copied text")
    }

    func testDownloadedSVGMustBeUTF8Markup() {
        XCTAssertEqual(ExtensionItemCopy.downloadedText(Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8), kind: .svg), #"<svg xmlns="http://www.w3.org/2000/svg"/>"#)
        XCTAssertNotNil(ExtensionItemCopy.downloadedText(Data("\u{FEFF}\n  <?xml version=\"1.0\"?>\n<svg/>".utf8), kind: .svg))
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<?xml version=\"1.0\"?><html/>".utf8), kind: .svg), "A prolog without an svg element")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<html><svg/></html>".utf8), kind: .svg))
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data([0x89, 0x50, 0x4E, 0x47]), kind: .svg), "PNG bytes are not SVG")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data([0x3C, 0x73, 0x76, 0x67, 0xFF]), kind: .svg), "Invalid UTF-8")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<svg>\0</svg>".utf8), kind: .svg), "NUL characters")
        XCTAssertEqual(ExtensionItemCopy.downloadedText(Data("plain words".utf8), kind: .text), "plain words")
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data(), kind: .text))
        XCTAssertNil(ExtensionItemCopy.downloadedText(Data("<svg/>".utf8), kind: .png), "Image kinds are never copied as text")
    }

    func testImageSignaturesMatchTheirKind() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let webp = Data("RIFF\0\0\0\0WEBPVP8 ".utf8)
        let ico = Data([0, 0, 1, 0, 1, 0])
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(png, kind: .png))
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(jpeg, kind: .jpeg))
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(webp, kind: .webp))
        XCTAssertTrue(ExtensionItemCopy.hasImageSignature(ico, kind: .ico))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(jpeg, kind: .png))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(png, kind: .webp))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(Data("<svg/>".utf8), kind: .ico))
        XCTAssertFalse(ExtensionItemCopy.hasImageSignature(png, kind: .svg))
    }

    func testErrorsExplainWhyNothingWasCopied() {
        XCTAssertEqual(ExtensionCopyError.hostNotApproved("assets.example.com").errorDescription, "Allow access to assets.example.com to copy this.")
        XCTAssertEqual(ExtensionCopyError.wrongType(.png).errorDescription, "The download isn’t a valid PNG image, so nothing was copied.")
        XCTAssertEqual(ExtensionCopyError.unavailable(404).errorDescription, "Couldn’t download it: the server answered 404. Nothing was copied.")
        XCTAssertEqual(ExtensionCopyError.tooLarge.errorDescription, "It’s larger than 512 KB, so nothing was copied.")
    }
}
