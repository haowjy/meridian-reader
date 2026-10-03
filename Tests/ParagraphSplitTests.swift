import AVFoundation
import SwiftData
import XCTest
@testable import Reader

/// Giant paragraphs split for display, navigation and audio.
/// Fixture text is public domain: Arthur Conan Doyle, "The Boscombe Valley Mystery" (1891).
final class ParagraphSplitTests: XCTestCase {
    /// Article HTML of one chapter page: 24 paragraphs of the story (three over the split
    /// threshold), spacer `&nbsp;` paragraphs, inline `<em>`, entities and a stray `<span>` with
    /// `<br>`s between blocks.
    static let chapterHTML = #"""
<p class="chapter-title"><strong>IV. THE BOSCOMBE VALLEY MYSTERY</strong></p>
<p class="para">&nbsp;</p>
<p class="para">&nbsp;</p>
<p class="para">“Boscombe Valley is a country district not very far from Ross, in Herefordshire. The largest landed proprietor in that part is a Mr. John Turner, who made his money in Australia and returned some years ago to the old country. One of the farms which he held, that of Hatherley, was let to Mr. Charles McCarthy, who was also an ex-Australian. The men had known each other in the colonies, so that it was not unnatural that when they came to settle down they should do so as near each other as possible. Turner was apparently the richer man, so McCarthy became his tenant but still remained, it seems, upon terms of perfect equality, as they were frequently together. McCarthy had one son, a lad of eighteen, and Turner had an only daughter of the same age, but neither of them had wives living. They appear to have avoided the society of the neighbouring English families and to have led retired lives, though both the McCarthys were fond of sport and were frequently seen at the race-meetings of the neighbourhood. McCarthy kept two servants—a man and a girl. Turner had a considerable household, some half-dozen at the least. That is as much as I have been able to gather about the families. Now for the facts.</p>
<p class="para">“On June 3rd, that is, on Monday last, McCarthy left his house at Hatherley about three in the afternoon and walked down to the Boscombe Pool, which is a small lake formed by the spreading out of the stream which runs down the Boscombe Valley. He had been out with his serving-man in the morning at Ross, and he had told the man that he must hurry, as he had an appointment of importance to keep at three. From that appointment he never came back alive.</p>
<p class="para">“From Hatherley Farmhouse to the Boscombe Pool is a quarter of a mile, and two people saw him as he passed over this ground. One was an old woman, whose name is not mentioned, and the other was William Crowder, a game-keeper in the employ of Mr. Turner. Both these witnesses depose that Mr. McCarthy was walking alone. The game-keeper adds that within a few minutes of his seeing Mr. McCarthy pass he had seen his son, Mr. James McCarthy, going the same way with a gun under his arm. To the best of his belief, the father was actually in sight at the time, and the son was following him. He thought no more of the matter until he heard in the evening of the tragedy that had occurred.</p>
<p class="para">“The two McCarthys were seen after the time when William Crowder, the game-keeper, lost sight of them. The Boscombe Pool is thickly wooded round, with just a fringe of grass and of reeds round the edge. A girl of fourteen, Patience Moran, who is the daughter of the lodge-keeper of the Boscombe Valley estate, was in one of the woods picking flowers. She states that while she was there she saw, at the border of the wood and close by the lake, Mr. McCarthy and his son, and that they appeared to be having a violent quarrel. She heard Mr. McCarthy the elder using very strong language to his son, and she saw the latter raise up his hand as if to strike his father. She was so frightened by their violence that she ran away and told her mother when she reached home that she had left the two McCarthys quarrelling near Boscombe Pool, and that she was afraid that they were going to fight. She had hardly said the words when young Mr. McCarthy came running up to the lodge to say that he had found his father dead in the wood, and to ask for the help of the lodge-keeper. He was much excited, without either his gun or his hat, and his right hand and sleeve were observed to be stained with fresh blood. On following him they found the dead body stretched out upon the grass beside the pool. The head had been beaten in by repeated blows of some heavy and blunt weapon. The injuries were such as might very well have been inflicted by the butt-end of his son’s gun, which was found lying on the grass within a few paces of the body. Under these circumstances the young man was instantly arrested, and a verdict of ‘wilful murder’ having been returned at the inquest on Tuesday, he was on Wednesday brought before the magistrates at Ross, who have referred the case to the next Assizes. Those are the main facts of the case as they came out before the coroner and the police-court.”</p>
<p class="para">“I could hardly imagine a more damning case,” I remarked. “If ever circumstantial evidence pointed to a criminal it does so here.”</p>
<p class="para">&ldquo;Circumstantial evidence is a very tricky thing,” answered Holmes thoughtfully. “It may seem to point very straight to one thing, but if you shift your own point of view a little, you may find it pointing in an equally uncompromising manner to something entirely different. It must be confessed, however, that the case looks exceedingly grave against the young man, and it is very possible that he is indeed the culprit. There are several people in the neighbourhood, however, and among them Miss Turner, the daughter of the neighbouring landowner, who believe in his innocence, and who have retained Lestrade, whom you may recollect in connection with the Study in Scarlet, to work out the case in his interest. Lestrade, being rather puzzled, has referred the case to me, and hence it is that two middle-aged gentlemen are flying westward at fifty miles an hour instead of quietly digesting their breakfasts at home.”</p>
<p class="para">“I am afraid,” said I, “that the facts are so obvious that you will find little credit to be gained out of this case.”</p>
<p class="para">“There is nothing more deceptive than an obvious fact,” he answered, laughing. “Besides, we may chance to hit upon some other obvious facts which may have been by no means obvious to Mr. Lestrade. You know me too well to think that I am boasting when I say that I shall either confirm or destroy his theory by means which he is quite incapable of employing, or even of understanding. To take the first example to hand, I very clearly perceive that in your bedroom the window is upon the right-hand side, and yet I question whether Mr. Lestrade would have noted even so self-evident a thing as that.”</p>
<p class="para">“How on earth&mdash;”</p>
<p class="para">“My dear fellow, I know you well. I know the military neatness which characterises you. You shave every morning, and in this season you shave by the sunlight; but since your shaving is less and less complete as we get farther back on the left side, until it becomes positively slovenly as we get round the angle of the jaw, it is surely very clear that that side is less illuminated than the other. I could not imagine a man of your habits looking at himself in an equal light and being satisfied with such a result. I only quote this as a trivial example of observation and inference. Therein lies my <em>métier</em>, and it is just possible that it may be of some service in the investigation which lies before us. There are one or two minor points which were brought out in the inquest, and which are worth considering.”</p>
<p class="para">“What are they?”</p>
<p class="para">“It appears that his arrest did not take place at once, but after the return to Hatherley Farm. On the inspector of constabulary informing him that he was a prisoner, he remarked that he was not surprised to hear it, and that it was no more than his deserts. This observation of his had the natural effect of removing any traces of doubt which might have remained in the minds of the coroner’s jury.”</p>
<span class="source-note"><br>Text: The Adventures of Sherlock Holmes (1892), public domain.<br></span>
<p class="para">“It was a confession,” I ejaculated.</p>
<p class="para">“No, for it was followed by a protestation of innocence.”</p>
<p class="para">“Coming on the top of such a damning series of events, it was at least a most suspicious remark.”</p>
<p class="para">“On the contrary,” said Holmes, “it is the brightest rift which I can at present see in the clouds. However innocent he might be, he could not be such an absolute imbecile as not to see that the circumstances were very black against him. Had he appeared surprised at his own arrest, or feigned indignation at it, I should have looked upon it as highly suspicious, because such surprise or anger would not be natural under the circumstances, and yet might appear to be the best policy to a scheming man. His frank acceptance of the situation marks him as either an innocent man, or else as a man of considerable self-restraint and firmness. As to his remark about his deserts, it was also not unnatural if you consider that he stood beside the dead body of his father, and that there is no doubt that he had that very day so far forgotten his filial duty as to bandy words with him, and even, according to the little girl whose evidence is so important, to raise his hand as if to strike him. The self-reproach and contrition which are displayed in his remark appear to me to be the signs of a healthy mind rather than of a guilty one.”</p>
<p class="para">&nbsp;</p>
<p class="para">I shook my head. “Many men have been hanged on far slighter evidence,” I remarked.</p>
<p class="para">“So they have. And many men have been wrongfully hanged.”</p>
<p class="para">“What is the young man’s own account of the matter?”</p>
<p class="para">“It is, I am afraid, not very encouraging to his supporters, though there are one or two points in it which are suggestive. You will find it here, and may read it for yourself.”</p>
<p class="para">He picked out from his bundle a copy of the local Herefordshire paper, and having turned down the sheet he pointed out the paragraph in which the unfortunate young man had given his own statement of what had occurred. I settled myself down in the corner of the carriage and read it very carefully. It ran in this way:</p>
<p class="para">“Mr. James McCarthy, the only son of the deceased, was then called and gave evidence as follows: ‘I had been away from home for three days at Bristol, and had only just returned upon the morning of last Monday, the 3rd. My father was absent from home at the time of my arrival, and I was informed by the maid that he had driven over to Ross with John Cobb, the groom. Shortly after my return I heard the wheels of his trap in the yard, and, looking out of my window, I saw him get out and walk rapidly out of the yard, though I was not aware in which direction he was going. I then took my gun and strolled out in the direction of the Boscombe Pool, with the intention of visiting the rabbit warren which is upon the other side. On my way I saw William Crowder, the game-keeper, as he had stated in his evidence; but he is mistaken in thinking that I was following my father. I had no idea that he was in front of me. When about a hundred yards from the pool I heard a cry of “Cooee!” which was a usual signal between my father and myself. I then hurried forward, and found him standing by the pool. He appeared to be much surprised at seeing me and asked me rather roughly what I was doing there. A conversation ensued which led to high words and almost to blows, for my father was a man of a very violent temper. Seeing that his passion was becoming ungovernable, I left him and returned towards Hatherley Farm. I had not gone more than 150 yards, however, when I heard a hideous outcry behind me, which caused me to run back again. I found my father expiring upon the ground, with his head terribly injured. I dropped my gun and held him in my arms, but he almost instantly expired. I knelt beside him for some minutes, and then made my way to Mr. Turner’s lodge-keeper, his house being the nearest, to ask for assistance. I saw no one near my father when I returned, and I have no idea how he came by his injuries. He was not a popular man, being somewhat cold and forbidding in his manners, but he had, as far as I know, no active enemies. I know nothing further of the matter.’</p>
<p class="para">“The Coroner: Did your father make any statement to you before he died?</p>
<p class="para">“Witness: He mumbled a few words, but I could only catch some allusion to a rat.</p>
<p class="para">&nbsp;</p>
"""#

    private var inquest: String { HierarchicalChunkerTests.inquest }

    private func endsSentence(_ s: String) -> Bool {
        var t = Substring(s)
        while let c = t.last, "\"'”’)]»".contains(c) { t = t.dropLast() }
        return t.last.map { ".!?…".contains($0) } ?? false
    }

    // MARK: Text splitter

    func testGiantParagraphSplitsIntoThreeBalancedPiecesAtSentenceEnds() {
        XCTAssertEqual(inquest.count, 1881)
        let pieces = ParagraphSplitter.pieces(inquest)
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.map(\.count), [666, 624, 589])
        XCTAssertTrue(pieces.allSatisfy { (500...900).contains($0.count) }, "\(pieces.map(\.count))")
        XCTAssertTrue(pieces.allSatisfy(endsSentence))
        XCTAssertTrue(pieces[1].hasPrefix("She was so frightened by their violence"))
        XCTAssertTrue(pieces[2].hasPrefix("The head had been beaten in"))
        XCTAssertEqual(pieces.joined(separator: " "), inquest, "text reassembles exactly")
    }

    func testCutOffsetsReassembleByteExact() {
        for para in [inquest, HierarchicalChunkerTests.testimony] {
            let offs = ParagraphSplitter.pieceStartUTF8Offsets(para)
            XCTAssertFalse(offs.isEmpty)
            let bytes = Array(para.utf8)
            var rebuilt: [String] = []
            var start = 0
            for o in offs + [bytes.count] {
                rebuilt.append(String(decoding: bytes[start..<o], as: UTF8.self))
                start = o
            }
            XCTAssertEqual(rebuilt.joined(), para)
            XCTAssertEqual(rebuilt.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, ParagraphSplitter.pieces(para))
        }
    }

    func testChapterParagraphsOverThresholdOnlyAndBalanced() {
        let paras = ListenHTMLBlocks.leafTexts(fromHTML: Self.chapterHTML)
        var splitSizes: [[Int]] = []
        for p in paras {
            let pieces = ParagraphSplitter.pieces(p)
            if p.count <= ParagraphSplitter.threshold {
                XCTAssertEqual(pieces, [p], "never split ≤ 1,200 chars")
                continue
            }
            XCTAssertGreaterThan(pieces.count, 1)
            XCTAssertEqual(pieces.joined(separator: " "), p)
            XCTAssertTrue(pieces.dropLast().allSatisfy(endsSentence), "cut mid-sentence: \(pieces.map { $0.suffix(30) })")
            let sizes = pieces.map(\.count)
            XCTAssertLessThanOrEqual(Double(sizes.max()!) / Double(sizes.min()!), 1.3, "balanced: \(sizes)")
            splitSizes.append(sizes)
        }
        // Opening paragraph 1,210 → 2; inquest summary 1,881 → 3; testimony 2,083 → 3. The
        // 1,135-char paragraph stays whole.
        XCTAssertEqual(splitSizes, [[664, 545], [666, 624, 589], [728, 684, 669]])
    }

    func testNoSplitWhenOnlyUnbalancedCutsExist() {
        let long = String(repeating: "word ", count: 235) + "end."          // one 1,179-char sentence
        let para = long + " " + "Short tail sentence here, only a little text."
        XCTAssertGreaterThan(para.count, 1200)
        XCTAssertEqual(ParagraphSplitter.pieces(para), [para], "a tiny tail is not worth a split")
        let oneSentence = String(repeating: "and so on ", count: 150) + "done."
        XCTAssertEqual(ParagraphSplitter.pieces(oneSentence), [oneSentence], "a single giant sentence stays whole")
    }

    func testAbbreviationsAndInitialsAreNotCutPoints() {
        let s1 = String(repeating: "The committee met again today and argued for a long while. ", count: 10)
        let mid = "Captain J. Hollis met Dr. Smith in the U.S.A. with etc-. The talks went well. "
        let para = (s1 + mid + s1).trimmingCharacters(in: .whitespaces)
        let pieces = ParagraphSplitter.pieces(para)
        XCTAssertGreaterThan(pieces.count, 1)
        for p in pieces {
            XCTAssertFalse(p.hasSuffix("I.") || p.hasSuffix("Dr.") || p.hasPrefix("Hollis") || p.hasPrefix("Smith"))
        }
    }

    // MARK: HTML (display) == listen list

    func testHTMLSplitMatchesTextSplitOnTheChapter() {
        let before = ListenHTMLBlocks.leafTexts(fromHTML: Self.chapterHTML)
        let split = ListenHTMLBlocks.splitLongBlocks(Self.chapterHTML)
        let after = ListenHTMLBlocks.leafTexts(fromHTML: split)
        XCTAssertEqual(after, before.flatMap(ParagraphSplitter.pieces))
        XCTAssertEqual(after.count, before.count + 5)
        // Only tags were inserted: removing them gives back the same text.
        func strip(_ h: String) -> String {
            h.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }
        XCTAssertEqual(strip(split), strip(Self.chapterHTML))
        XCTAssertEqual(split.components(separatedBy: "<p").count, Self.chapterHTML.components(separatedBy: "<p").count + 5)
        XCTAssertEqual(ListenHTMLBlocks.splitLongBlocks(split), split, "idempotent")
    }

    func testHTMLSplitClosesAndReopensInlineTagsAndDropsIDs() {
        let s = String(repeating: "Plain words fill this sentence up nicely. ", count: 16)
        let html = #"<p id="big" class="c">"# + s + #"<em class="x">An emphasised sentence ends here. And "#
            + #"it continues</em> <a href="u">"# + s + "</a> &ldquo;Quoted end.&rdquo; " + s + "</p><p id=\"small\">Tiny.</p>"
        let out = ListenHTMLBlocks.splitLongBlocks(html)
        let before = ListenHTMLBlocks.leafTexts(fromHTML: html)
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: out), before.flatMap(ParagraphSplitter.pieces))
        XCTAssertGreaterThan(ListenHTMLBlocks.leafTexts(fromHTML: out).count, 2)
        XCTAssertEqual(out.components(separatedBy: "id=\"big\"").count, 2, "id kept once")
        XCTAssertEqual(out.components(separatedBy: "<em").count, out.components(separatedBy: "</em>").count)
        XCTAssertEqual(out.components(separatedBy: "<a ").count, out.components(separatedBy: "</a>").count)
        XCTAssertTrue(out.contains(#"class="c""#))
    }

    func testReaderViewIndicesMatchListenParagraphs() {
        let extracted = ExtractedArticle(title: "The Boscombe Valley Mystery", siteName: "Example Classics",
                                         cleanedHTML: Self.chapterHTML, plainText: "", excerpt: "")
        let article = ReaderArticle(id: UUID(), url: URL(string: "https://example.com/classics/boscombe-valley")!,
                                    extracted: extracted)
        // What the web view indexes (displayHTML leaves) is exactly the listen / queue list.
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: article.displayHTML), article.document.paragraphs)
        XCTAssertTrue(article.document.paragraphs.allSatisfy { $0.count <= ParagraphSplitter.threshold })
    }

    func testPlainTextPathSplitsTheSameWay() {
        let doc = ParagraphDocument(plainText: "Title\n\n" + inquest + "\n\nAfter.")
        XCTAssertEqual(doc.paragraphs, ["Title"] + ParagraphSplitter.pieces(inquest) + ["After."])
        XCTAssertEqual(ParagraphDocument(plainText: "Title\n\n" + inquest, splitLong: false).count, 2)
    }

    // MARK: Position mapping

    func testPositionMapsToSameSentence() {
        let old = ParagraphDocument(parts: ListenHTMLBlocks.leafTexts(fromHTML: Self.chapterHTML))
        let new = ParagraphDocument(html: ListenHTMLBlocks.splitLongBlocks(Self.chapterHTML))
        let iGiant = old.paragraphs.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let first = iGiant + 1 // the opening paragraph's split shifts the giant's first piece by one
        let text = old.paragraphs[iGiant] as NSString
        let inPiece2 = old.utf16Ranges[iGiant].location + text.range(of: "She was so frightened").location
        let midWord = old.utf16Ranges[iGiant].location + text.range(of: "repeated").location + 3
        let p = ParagraphPositionMap.map(paragraph: iGiant, utf16Offset: inPiece2, from: old, to: new)
        XCTAssertEqual(p.paragraph, first + 1)
        XCTAssertTrue(new.paragraphs[p.paragraph].hasPrefix("She was so frightened"))
        XCTAssertEqual(p.utf16Offset, new.utf16Ranges[first + 1].location)
        let q = ParagraphPositionMap.map(paragraph: iGiant, utf16Offset: midWord, from: old, to: new)
        XCTAssertEqual(q.paragraph, first + 2)
        XCTAssertEqual((new.joinedText as NSString).substring(with: NSRange(location: q.utf16Offset, length: 4)), "eate")
        // Stale offset (not inside the paragraph) → paragraph start → first piece.
        XCTAssertEqual(ParagraphPositionMap.map(paragraph: iGiant, utf16Offset: 0, from: old, to: new).paragraph, first)
        // Later paragraphs shift by the number of extra pieces before them.
        let iLast = old.count - 1
        XCTAssertEqual(ParagraphPositionMap.mapParagraphStart(iLast, from: old, to: new), new.count - 1)
        let iAfter = iGiant + 1 // unsplit paragraph right after the giant
        XCTAssertEqual(new.paragraphs[ParagraphPositionMap.mapParagraphStart(iAfter, from: old, to: new)], old.paragraphs[iAfter])
    }
}

/// Migration of saved articles + their audio cache to layout v3.
@MainActor
final class ParagraphLayoutMigrationTests: XCTestCase {
    private var cleanups: [() -> Void] = []
    override func tearDown() {
        cleanups.forEach { $0() }
        cleanups = []
        ListenResumePointStore.shared.clear()
        super.tearDown()
    }

    private func makeCoordinator() -> LocalTTSCoordinator {
        let suite = "LayoutMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("LayoutMig-\(UUID().uuidString)")
        let guardDir = tmp.appendingPathComponent("LayoutMigGuard-\(UUID().uuidString)")
        cleanups.append {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: guardDir)
        }
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), KokoroStubProvider()], gate: { _ in true })
        return LocalTTSCoordinator(engines: registry, defaults: defaults, audioCache: ArticleAudioCache(root: root),
                                   crashGuard: EngineCrashGuard(directory: guardDir))
    }

    /// A stitched paragraph CAF like the queue writes: chunk k = `lengths[k]` samples of value k+1.
    private func writeStitched(_ cache: ArticleAudioCache, article: UUID, index: Int, text: String,
                               lengths: [Int]) throws {
        var samples: [Float] = []
        for (k, n) in lengths.enumerated() { samples += [Float](repeating: Float(k + 1) / 100, count: n) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stitch-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: tmp)
        try cache.storeParagraph(articleID: article, paragraphIndex: index, sourceURL: tmp,
                                 duration: Double(samples.count) / 24_000, engineID: SpeechEngineID.kokoro.rawValue,
                                 voiceID: "kstub:af_heart", text: text,
                                 chunkDurations: lengths.count > 1 ? lengths.map { Double($0) / 24_000 } : nil)
    }

    private func int16Samples(_ url: URL) throws -> [Int16] {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: b)
        return Array(UnsafeBufferPointer(start: b.int16ChannelData![0], count: Int(b.frameLength)))
    }

    func testSavedArticleMigrationKeepsPositionAndOnlyInvalidatesSplitAudio() throws {
        let coordinator = makeCoordinator()
        let cache = coordinator.audioCache
        let container = try ModelContainer(for: SavedArticle.self, RecentVisit.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let html = ParagraphSplitTests.chapterHTML
        let title = "The Boscombe Valley Mystery"
        let oldList = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false)
        let iGiant = oldList.paragraphs.firstIndex { $0.hasPrefix("“The two McCarthys were seen") }!
        let first = iGiant + 1 // the opening paragraph's split shifts the giant's first piece by one
        let oldGiant = oldList.paragraphs[iGiant] as NSString
        let offset = oldList.utf16Ranges[iGiant].location + oldGiant.range(of: "The head had been beaten").location

        let row = SavedArticle(urlString: "https://example.com/classics/boscombe-valley",
                               title: title, siteDomain: "example.com", cleanedHTML: html, plainText: "",
                               wordCount: 2000, estimatedMinutes: 10, excerpt: "",
                               playbackParagraphIndex: iGiant, playbackUTF16Offset: offset)
        row.listenBlocksData = try JSONEncoder().encode(oldList.paragraphs)
        row.listenBlocksVersion = 2
        context.insert(row)
        try context.save()

        // Audio as rendered before the split: the giant, the paragraph after it and the last one.
        let giantPlan = TextChunker.chunks(for: oldList.paragraphs[iGiant], limits: .kokoroCPU)
        let lengths = giantPlan.indices.map { 2400 + 240 * $0 }
        try writeStitched(cache, article: row.id, index: iGiant, text: oldList.paragraphs[iGiant], lengths: lengths)
        let iAfter = iGiant + 1
        try writeStitched(cache, article: row.id, index: iAfter, text: oldList.paragraphs[iAfter], lengths: [4800])
        let iLast = oldList.count - 1
        try writeStitched(cache, article: row.id, index: iLast, text: oldList.paragraphs[iLast], lengths: [4800])
        ListenResumePointStore.shared.save(article: row.id, paragraph: iAfter)
        // A crash-resume target read at coordinator init (before migration) — old numbering.
        coordinator.pendingResume = ListenResumeTarget(articleKey: row.id.uuidString, paragraph: iAfter, at: Date())

        let report = ArticleLibrary.migrateParagraphLayout(in: context, localTTS: coordinator)
        XCTAssertEqual(report.articles, 1)
        XCTAssertEqual(report.newParagraphs, report.oldParagraphs + 5)
        XCTAssertEqual(report.splitParagraphs, 3)

        let new = row.listenDocument()
        XCTAssertEqual(row.listenBlocksVersion, ListenHTMLBlocks.version)
        XCTAssertEqual(new.paragraphs, ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title).paragraphs)
        // Position: same sentence ("The head had been beaten…" starts the giant's third piece).
        XCTAssertEqual(row.playbackParagraphIndex, first + 2)
        XCTAssertTrue(new.paragraphs[row.playbackParagraphIndex].hasPrefix("The head had been beaten"))
        XCTAssertEqual(row.playbackUTF16Offset, new.utf16Ranges[first + 2].location)
        // Crash-resume point follows its paragraph.
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, iAfter + 3)
        XCTAssertEqual(coordinator.pendingResume?.paragraph, iAfter + 3, "in-memory crash target remapped too")

        // Unsplit paragraphs keep their audio at the shifted index.
        let entryAfter = cache.entry(articleID: row.id, paragraphIndex: iAfter + 3)
        XCTAssertEqual(entryAfter?.textHash, ArticleIdentity.paragraphHash(oldList.paragraphs[iAfter]))
        XCTAssertEqual(cache.entry(articleID: row.id, paragraphIndex: new.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(oldList.paragraphs[iLast]))
        // Split paragraph: a piece keeps audio only if its chunk plan lines up with the old chunks.
        var from = 0
        for k in 0..<3 {
            let piece = new.paragraphs[first + k]
            let plan = TextChunker.chunks(for: piece, limits: .kokoroCPU)
            var q: Int?
            var s = from
            while s + plan.count <= giantPlan.count {
                if Array(giantPlan[s..<(s + plan.count)]) == plan { q = s; break }
                s += 1
            }
            let entry = cache.entry(articleID: row.id, paragraphIndex: first + k)
            guard let q else { XCTAssertNil(entry, "misaligned piece \(k) must re-render"); continue }
            from = q + plan.count
            let e = try XCTUnwrap(entry, "aligned piece \(k) keeps audio")
            XCTAssertEqual(e.textHash, ArticleIdentity.paragraphHash(piece))
            let samples = try int16Samples(cache.directory(for: row.id).appendingPathComponent(e.file))
            XCTAssertEqual(samples.count, lengths[q..<(q + plan.count)].reduce(0, +), "sample-exact slice")
            XCTAssertEqual(samples.first, Int16(Float(q + 1) / 100 * 32767))
            XCTAssertEqual(samples.last, Int16(Float(q + plan.count) / 100 * 32767))
        }
        XCTAssertNotNil(cache.entry(articleID: row.id, paragraphIndex: first), "the giant's first piece lines up with its old first chunks")
        // Idempotent.
        XCTAssertEqual(ArticleLibrary.migrateParagraphLayout(in: context, localTTS: coordinator).articles, 0)
    }

    func testBrowseOpenAlignsEphemeralCacheTheSameWay() throws {
        let coordinator = makeCoordinator()
        let cache = coordinator.audioCache
        let html = ParagraphSplitTests.chapterHTML
        let url = URL(string: "https://example.com/classics/boscombe-valley")!
        let extracted = ExtractedArticle(title: "Boscombe", siteName: nil, cleanedHTML: html, plainText: "", excerpt: "")
        let article = ReaderArticle(id: ArticleIdentity.articleKey(url: url), url: url, extracted: extracted)
        let oldList = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: "Boscombe", splitLong: false)
        let iLast = oldList.count - 1
        try writeStitched(cache, article: article.id, index: iLast, text: oldList.paragraphs[iLast], lengths: [4800])
        coordinator.prepareListenIdentity(key: article.id, paragraphs: article.document.paragraphs)
        XCTAssertEqual(cache.entry(articleID: article.id, paragraphIndex: article.document.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(oldList.paragraphs[iLast]))
        XCTAssertNil(cache.entry(articleID: article.id, paragraphIndex: iLast))
    }
}
