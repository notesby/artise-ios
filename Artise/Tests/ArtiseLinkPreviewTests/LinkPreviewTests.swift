//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseLinkPreview
import Foundation
import Testing

struct LinkPreviewTests {
    private let draft = DraftLinkPreview(url: "https://cocina.example/mole", title: "Mole", description: "La receta", siteName: "Cocina",
                                         image: DraftLinkPreviewImage(data: Data([1, 2, 3]), width: 800, height: 420))
    
    /// The first web link is found, without the punctuation around it; chat links (matrix.to) are skipped.
    @Test
    func findsTheLinkToPreview() {
        #expect(LinkFinder.firstLink("mira https://www.youtube.com/watch?v=abc123.") == "https://www.youtube.com/watch?v=abc123")
        #expect(LinkFinder.firstLink("(ver https://es.wikipedia.org/wiki/Mole_(salsa))") == "https://es.wikipedia.org/wiki/Mole_(salsa)")
        #expect(LinkFinder.firstLink("en www.artise.co, ¿la viste?") == "https://www.artise.co")
        #expect(LinkFinder.firstLink("https://matrix.to/#/@ana:artise.co y http://example.com/a") == "http://example.com/a")
        #expect(LinkFinder.firstLink("nada aquí, ni https:// ni www") == nil)
        #expect(LinkFinder.firstLink("https://localhost/x") == nil)
    }
    
    /// Open Graph tags first, then Twitter's, then the page's own title and description; relative pictures resolved.
    @Test
    func readsWhatAPageSaysAboutItself() throws {
        let page = """
        <html><head>
          <title>Ignored title</title>
          <meta property="og:title" content="  Mole   poblano &amp; arroz ">
          <meta name="twitter:description" content='La receta de la abuela'>
          <meta content="Cocina" property="og:site_name">
          <meta property="og:image" content="/img/mole.jpg">
        </head><body>…</body></html>
        """
        let pageURL = try #require(URL(string: "https://cocina.example/recetas/mole"))
        #expect(PageMetadata.parse(page, pageURL: pageURL)
            == PageMetadata(title: "Mole poblano & arroz", description: "La receta de la abuela", siteName: "Cocina",
                            imageURL: "https://cocina.example/img/mole.jpg"))
        let example = try #require(URL(string: "https://example.com"))
        #expect(PageMetadata.parse("<title>Example Domain</title><meta name=description content=Hola>", pageURL: example)
            == PageMetadata(title: "Example Domain", description: "Hola", siteName: nil, imageURL: nil))
        #expect(PageMetadata.parse("<p>nada</p>", pageURL: example).isEmpty)
        #expect(PageMetadata.parse("<title>\(String(repeating: "a", count: 500))</title>", pageURL: example).title?.count == 200)
        #expect(PageMetadata.parse("<TITLE>Caf&#233; &#x2014; Men&uacute;</TITLE>", pageURL: example).title == "Café — Men&uacute;")
    }
    
    /// A page in Latin-1 that says so is read in Latin-1.
    @Test
    func readsThePagesEncoding() throws {
        let html = "<meta charset=\"iso-8859-1\"><title>Café</title>"
        let data = try #require(html.data(using: .isoLatin1))
        let pageURL = try #require(URL(string: "https://example.com"))
        #expect(PageMetadata.parse(data, charset: nil, pageURL: pageURL).title == "Café")
    }
    
    #if canImport(CommonCrypto) && canImport(CryptoKit)
    /// What's encrypted decrypts back, with the hash checked; every file gets its own key.
    @Test
    func encryptsPicturesForEncryptedChats() throws {
        let plain = Data((0..<5000).map { UInt8($0 % 256) })
        let first = try AttachmentEncryption.encrypt(plain)
        #expect(first.data != plain)
        #expect(try AttachmentEncryption.decrypt(first) == plain)
        #expect(try AttachmentEncryption.encrypt(plain).key != first.key)
        // The counter half of the IV starts at zero, as Matrix asks.
        let iv = try #require(Data(base64Encoded: first.iv + "=="))
        #expect(iv.suffix(8).allSatisfy { $0 == 0 })
        // A changed file fails its hash.
        let tampered = EncryptedAttachment(data: Data(first.data.reversed()), key: first.key, iv: first.iv, sha256: first.sha256)
        #expect(throws: AttachmentEncryptionError.hashMismatch) { try AttachmentEncryption.decrypt(tampered) }
    }
    #endif
    
    /// In a plain chat the picture is an mxc URL; in an encrypted one it's an encrypted file the reader turns into a source.
    @Test
    func previewsGoInTheMessageAndComeBackOut() throws {
        let plain = LinkPreviewContent.build(draft, image: UploadedImage(mxcURL: "mxc://artise.co/plain", width: 800, height: 420, size: 1234, encryption: nil))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any])
        let entry = try #require((root["com.beeper.linkpreviews"] as? [[String: Any]])?.first)
        #expect(entry["og:image"] as? String == "mxc://artise.co/plain")
        #expect(entry["matched_url"] as? String == "https://cocina.example/mole")
        let event = #"{"type": "m.room.message", "content": {"body": "x", "com.beeper.linkpreviews": \#(String(plain.dropFirst(#"{"com.beeper.linkpreviews":"#.count).dropLast()))}}"#
        let read = try #require(LinkPreviewContent.read(event))
        #expect(read.title == "Mole")
        #expect(read.image?.encryptedSourceJSON == nil)
        #expect(read.image?.width == 800)
        
        let encryption = EncryptedAttachment(data: Data([9]), key: "a2V5", iv: "aXY", sha256: "aGFzaA")
        let encrypted = LinkPreviewContent.build(draft, image: UploadedImage(mxcURL: "mxc://artise.co/secret", width: 800, height: 420, size: 1234, encryption: encryption))
        let readEncrypted = try #require(LinkPreviewContent.read(encrypted))
        let source = try #require(readEncrypted.image?.encryptedSourceJSON)
        let file = try #require(try (JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any])?["file"] as? [String: Any])
        #expect(file["url"] as? String == "mxc://artise.co/secret")
        #expect((file["key"] as? [String: Any])?["alg"] as? String == "A256CTR")
        #expect(Set(file.keys).isSuperset(of: ["iv", "hashes", "v"]))
        #expect(!encrypted.contains("og:image\""))
        
        // Without a picture, and with nothing readable, there's no preview.
        let noImage = DraftLinkPreview(url: draft.url, title: draft.title, description: draft.description, siteName: draft.siteName, image: nil)
        #expect(LinkPreviewContent.read(LinkPreviewContent.build(noImage, image: nil))?.image == nil)
        #expect(LinkPreviewContent.read(#"{"content": {"com.beeper.linkpreviews": [{"matched_url": "https://a.b"}]}}"#) == nil)
        #expect(LinkPreviewContent.read("not json") == nil)
        // MSC4095's stable name is read too.
        #expect(LinkPreviewContent.read(#"{"m.url_previews": [{"matched_url": "https://a.b", "og:title": "T"}]}"#)?.title == "T")
    }
    
    /// The card names the site, else its address without "www.".
    @Test
    func siteLabel() {
        #expect(draft.siteLabel == "Cocina")
        #expect(DraftLinkPreview(url: "https://www.example.com/a", title: "T", description: nil, siteName: nil, image: nil).siteLabel == "example.com")
    }
}
