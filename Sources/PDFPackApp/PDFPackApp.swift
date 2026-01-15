import SwiftUI
import AppKit
import PDFKit
import CoreText
import UniformTypeIdentifiers

@main
struct PDFPackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct ContentView: View {
    @State private var items: [PDFItem] = []
    @State private var selection = Set<UUID>()
    @State private var alertMessage: String?
    @State private var isGenerating = false
    @State private var selectedItem: PDFItem?
    @State private var generatedDocument: PDFDocument?
    @State private var showingPreview = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Add Files") {
                    addFiles()
                }
                Button("Load Pack") {
                    loadPack()
                }
                Button("Save Pack") {
                    savePack()
                }
                .disabled(items.isEmpty)
                Button("Remove Selected") {
                    removeSelected()
                }
                .disabled(selection.isEmpty)
                Button("Move Up") {
                    moveSelection(by: -1)
                }
                .disabled(selection.count != 1)
                Button("Move Down") {
                    moveSelection(by: 1)
                }
                .disabled(selection.count != 1)
                Spacer()
                Button("Generate PDF") {
                    generatePDF()
                }
                .disabled(items.isEmpty || isGenerating)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                List(selection: $selection) {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.url.lastPathComponent)
                                    .font(.headline)
                                Spacer()
                                Text(item.type.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Title")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Add a title", text: $item.title)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Add a short description", text: $item.description)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .frame(minWidth: 520)

                PreviewPane(item: selectedItem)
                    .frame(minWidth: 320)
            }
            .frame(minWidth: 900, minHeight: 520)
        }
        .padding(.vertical)
        .alert("PDFPack", isPresented: Binding(get: {
            alertMessage != nil
        }, set: { newValue in
            if !newValue {
                alertMessage = nil
            }
        })) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showingPreview) {
            GeneratedPreviewSheet(
                document: generatedDocument,
                onSave: saveGeneratedPDF,
                onCancel: {
                    generatedDocument = nil
                    showingPreview = false
                }
            )
        }
        .onChange(of: selection) { newSelection in
            if let id = newSelection.first {
                selectedItem = items.first(where: { $0.id == id })
            } else {
                selectedItem = nil
            }
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let wordDoc = UTType(filenameExtension: "doc")
        let wordDocx = UTType(filenameExtension: "docx")
        panel.allowedContentTypes = [
            .pdf,
            .plainText,
            .png,
            .jpeg,
            .tiff,
            .image,
            wordDoc,
            wordDocx
        ].compactMap { $0 }
        if panel.runModal() == .OK {
            for url in panel.urls {
                let title = url.deletingPathExtension().lastPathComponent
                let type = PDFItemType.from(url: url)
                let item = PDFItem(url: url, title: title, description: "", type: type)
                items.append(item)
            }
        }
    }

    private func savePack() {
        let savePanel = NSSavePanel()
        let packType = UTType(filenameExtension: "pack") ?? .data
        savePanel.allowedContentTypes = [packType]
        savePanel.nameFieldStringValue = "Untitled.pack"
        if savePanel.runModal() != .OK {
            return
        }
        guard let url = savePanel.url else {
            return
        }
        let pack = PackFile(items: items.map { item in
            PackItem(path: item.url.path, title: item.title, description: item.description)
        })
        do {
            let data = try JSONEncoder().encode(pack)
            try data.write(to: url)
            alertMessage = "Saved pack to \(url.path)"
        } catch {
            alertMessage = "Failed to save pack: \(error.localizedDescription)"
        }
    }

    private func loadPack() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let packType = UTType(filenameExtension: "pack") ?? .data
        panel.allowedContentTypes = [packType]
        if panel.runModal() != .OK {
            return
        }
        guard let url = panel.url else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let pack = try JSONDecoder().decode(PackFile.self, from: data)
            var loadedItems: [PDFItem] = []
            var missingCount = 0
            for entry in pack.items {
                let fileURL = URL(fileURLWithPath: entry.path)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    missingCount += 1
                    continue
                }
                let type = PDFItemType.from(url: fileURL)
                let item = PDFItem(url: fileURL, title: entry.title, description: entry.description, type: type)
                loadedItems.append(item)
            }
            items = loadedItems
            selection.removeAll()
            selectedItem = nil
            if missingCount > 0 {
                alertMessage = "Loaded pack with \(missingCount) missing files."
            } else {
                alertMessage = "Loaded pack from \(url.lastPathComponent)"
            }
        } catch {
            alertMessage = "Failed to load pack: \(error.localizedDescription)"
        }
    }

    private func removeSelected() {
        items.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func moveSelection(by offset: Int) {
        guard selection.count == 1, let id = selection.first else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        let newIndex = max(0, min(items.count - 1, index + offset))
        guard newIndex != index else {
            return
        }
        let item = items.remove(at: index)
        items.insert(item, at: newIndex)
        selection = [item.id]
    }

    private func generatePDF() {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let doc = try PDFBuilder.buildPDF(items: items)
            generatedDocument = doc
            showingPreview = true
        } catch {
            alertMessage = "Failed to build PDF: \(error.localizedDescription)"
        }
    }

    private func saveGeneratedPDF() {
        guard let doc = generatedDocument else {
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Combined.pdf"
        if savePanel.runModal() != .OK {
            return
        }
        guard let url = savePanel.url else {
            return
        }
        do {
            guard let data = doc.dataRepresentation() else {
                throw PDFBuilderError.exportFailed
            }
            try data.write(to: url)
            alertMessage = "Saved PDF to \(url.path)"
            showingPreview = false
            generatedDocument = nil
        } catch {
            alertMessage = "Failed to save PDF: \(error.localizedDescription)"
        }
    }
}

struct PDFItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    var description: String
    let type: PDFItemType
}

struct PackItem: Codable {
    let path: String
    let title: String
    let description: String
}

struct PackFile: Codable {
    let items: [PackItem]
}

struct PreviewPane: View {
    let item: PDFItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
            Group {
                if let item = item {
                    PreviewContent(item: item)
                } else {
                    Text("Select a file to preview.")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .padding(.trailing, 8)
    }
}

struct PreviewContent: View {
    let item: PDFItem

    var body: some View {
        switch item.type {
        case .pdf:
            PDFPreview(url: item.url)
        case .image:
            ImagePreview(url: item.url)
        case .text:
            TextPreview(url: item.url)
        case .word:
            WordPreview(url: item.url)
        case .unknown:
            Text("Unsupported file type.")
                .foregroundColor(.secondary)
        }
    }
}

struct GeneratedPreviewSheet: View {
    let document: PDFDocument?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("PDF Preview")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                Button("Save PDF") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)

            if let document = document {
                GeneratedPDFView(document: document)
            } else {
                Text("No preview available.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .padding(.vertical)
    }
}

struct GeneratedPDFView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor.windowBackgroundColor
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor.windowBackgroundColor
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}

struct ImagePreview: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            Text("Unable to load image.")
                .foregroundColor(.secondary)
        }
    }
}

struct TextPreview: View {
    let url: URL

    var body: some View {
        let contents = (try? String(contentsOf: url)) ?? ""
        ScrollView {
            Text(contents.isEmpty ? "(Empty text file)" : contents)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
    }
}

struct WordPreview: View {
    let url: URL

    var body: some View {
        let attributed = PDFBuilder.loadWordAttributedString(url: url)
        let content = AttributedString(attributed)
        ScrollView {
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
    }
}

enum PDFItemType: String {
    case pdf
    case image
    case text
    case word
    case unknown

    var displayName: String {
        switch self {
        case .pdf:
            return "PDF"
        case .image:
            return "Image"
        case .text:
            return "Text"
        case .word:
            return "Word"
        case .unknown:
            return "Unknown"
        }
    }

    static func from(url: URL) -> PDFItemType {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if type.conforms(to: .pdf) {
                return .pdf
            }
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .plainText) {
                return .text
            }
            if type.conforms(to: UTType(filenameExtension: "doc") ?? .data) ||
                type.conforms(to: UTType(filenameExtension: "docx") ?? .data) {
                return .word
            }
        }
        let ext = url.pathExtension.lowercased()
        if ext == "txt" {
            return .text
        }
        if ext == "doc" || ext == "docx" {
            return .word
        }
        return .unknown
    }
}

struct TOCEntry {
    let title: String
    let description: String
    let page: Int
}

struct TOCLink {
    let tocPageIndex: Int
    let rect: CGRect
    let targetPageIndex: Int
}

enum PDFBuilderError: Error {
    case invalidImage
    case unsupportedFile
    case exportFailed
}

enum PDFBuilder {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 54
    private static let headerGap: CGFloat = 40

    static func buildPDF(items: [PDFItem]) throws -> PDFDocument {
        let contentDoc = PDFDocument()
        var entries: [TOCEntry] = []
        var contentHeaders: [String] = []
        var pageIndex = 0

        for item in items {
            let startPage = pageIndex + 1
            entries.append(TOCEntry(title: item.title, description: item.description, page: startPage))
            let section = try buildSection(for: item)
            for index in 0..<section.document.pageCount {
                if let page = section.document.page(at: index) {
                    contentDoc.insert(page, at: contentDoc.pageCount)
                }
            }
            contentHeaders.append(contentsOf: section.headers)
            pageIndex += section.document.pageCount
        }

        let tocPages = tocPageCount(for: entries)
        let tocResult = makeTableOfContents(entries: entries, pageOffset: tocPages)
        let tocDoc = tocResult.document
        let finalDoc = PDFDocument()

        for index in 0..<tocDoc.pageCount {
            if let page = tocDoc.page(at: index) {
                normalizeGeneratedPage(page)
                finalDoc.insert(page, at: finalDoc.pageCount)
            }
        }
        for index in 0..<contentDoc.pageCount {
            if let page = contentDoc.page(at: index) {
                finalDoc.insert(page, at: finalDoc.pageCount)
            }
        }
        addTOCLinks(links: tocResult.links, to: finalDoc)
        addHeadersAndFooters(contentHeaders: contentHeaders, tocPages: tocPages, to: finalDoc)
        return finalDoc
    }

    private static func buildSection(for item: PDFItem) throws -> (document: PDFDocument, headers: [String]) {
        let section = PDFDocument()
        var headers: [String] = []
        let headerText = makeHeaderText(for: item)

        switch item.type {
        case .pdf:
            guard let doc = PDFDocument(url: item.url) else {
                throw PDFBuilderError.unsupportedFile
            }
            for index in 0..<doc.pageCount {
                if let page = doc.page(at: index) {
                    section.insert(page, at: section.pageCount)
                    headers.append(headerText)
                }
            }
        case .image:
            guard let image = NSImage(contentsOf: item.url) else {
                throw PDFBuilderError.invalidImage
            }
            if let page = makeImagePage(image: image) {
                section.insert(page, at: section.pageCount)
                headers.append(headerText)
            }
        case .text:
            let text = (try? String(contentsOf: item.url)) ?? ""
            let textDoc = makeTextDocument(text: text)
            for index in 0..<textDoc.pageCount {
                if let page = textDoc.page(at: index) {
                    normalizeGeneratedPage(page)
                    section.insert(page, at: section.pageCount)
                    headers.append(headerText)
                }
            }
        case .word:
            let attributed = loadWordAttributedString(url: item.url)
            let wordDoc = makeAttributedDocument(attributed, topInset: headerGap)
            for index in 0..<wordDoc.pageCount {
                if let page = wordDoc.page(at: index) {
                    normalizeGeneratedPage(page)
                    section.insert(page, at: section.pageCount)
                    headers.append(headerText)
                }
            }
        case .unknown:
            throw PDFBuilderError.unsupportedFile
        }

        return (section, headers)
    }

    private static func makeImagePage(image: NSImage) -> PDFPage? {
        let doc = makeSinglePageDocument { context in
            let availableRect = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
            var rect = availableRect
            let imageSize = image.size
            if imageSize.width > 0 && imageSize.height > 0 {
                let scale = min(availableRect.width / imageSize.width, availableRect.height / imageSize.height)
                let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                rect = CGRect(
                    x: availableRect.midX - scaledSize.width / 2,
                    y: availableRect.midY - scaledSize.height / 2,
                    width: scaledSize.width,
                    height: scaledSize.height
                )
            }
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }
            context.draw(cgImage, in: rect)
        }
        return doc.page(at: 0)
    }

    private static func makeTextDocument(text: String) -> PDFDocument {
        let content = text.isEmpty ? "(Empty text file)" : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]
        let attributedText = NSAttributedString(string: content, attributes: attributes)
        return makeAttributedDocument(attributedText, topInset: headerGap)
    }

    private static func makeAttributedDocument(_ attributedText: NSAttributedString, topInset: CGFloat = 0) -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return PDFDocument()
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2 - topInset
        )
        var currentRange = CFRange(location: 0, length: 0)

        while currentRange.location < attributedText.length {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            let path = CGMutablePath()
            path.addRect(textRect)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visibleRange.length
            currentRange.length = 0
            context.endPDFPage()
        }

        context.closePDF()
        return PDFDocument(data: data as Data) ?? PDFDocument()
    }

    static func loadWordAttributedString(url: URL) -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        let docType: NSAttributedString.DocumentType = (ext == "docx") ? .officeOpenXML : .docFormat
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: docType
        ]
        if let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
            return attributed
        }
        if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return attributed
        }
        return NSAttributedString(string: "(Unable to load Word document.)")
    }

    private static func normalizeGeneratedPage(_ page: PDFPage) {
        page.rotation = 0
    }

    private static func makeSinglePageDocument(draw: (CGContext) -> Void) -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return PDFDocument()
        }

        context.beginPDFPage(nil)
        draw(context)
        context.endPDFPage()
        context.closePDF()

        return PDFDocument(data: data as Data) ?? PDFDocument()
    }

    private static func drawText(_ text: String, in rect: CGRect, font: NSFont, alignment: NSTextAlignment, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let path = CGMutablePath()
        path.addRect(rect)
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedText.length), path, nil)
        CTFrameDraw(frame, context)
    }

    private static func tocPageCount(for entries: [TOCEntry]) -> Int {
        let lineHeight: CGFloat = 18
        let headerHeight: CGFloat = 36
        let availableHeight = pageSize.height - margin * 2 - headerHeight
        let linesPerPage = max(1, Int(availableHeight / lineHeight))
        let pages = Int(ceil(Double(entries.count) / Double(linesPerPage)))
        return max(1, pages)
    }

    private static func makeTableOfContents(entries: [TOCEntry], pageOffset: Int) -> (document: PDFDocument, links: [TOCLink]) {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return (PDFDocument(), [])
        }

        let lineHeight: CGFloat = 16
        let headerHeight: CGFloat = 30
        let availableHeight = pageSize.height - margin * 2 - headerHeight
        let linesPerPage = max(1, Int(availableHeight / lineHeight))
        let pages = tocPageCount(for: entries)
        let titleFont = NSFont.boldSystemFont(ofSize: 20)
        let bodyFont = NSFont.systemFont(ofSize: 11)
        var links: [TOCLink] = []

        for pageIndex in 0..<pages {
            context.beginPDFPage(nil)
            let headerY = pageSize.height - margin - 28
            let headerRect = CGRect(x: margin, y: headerY, width: pageSize.width - margin * 2, height: 28)
            drawText("Table of Contents", in: headerRect, font: titleFont, alignment: .left, context: context)

            let startIndex = pageIndex * linesPerPage
            let endIndex = min(entries.count, startIndex + linesPerPage)
            var y = headerY - headerHeight
            for entryIndex in startIndex..<endIndex {
                let entry = entries[entryIndex]
                let pageNumber = entry.page + pageOffset
                let title = entry.description.isEmpty ? entry.title : "\(entry.title) - \(entry.description)"
                let textRect = CGRect(x: margin, y: y, width: pageSize.width - margin * 2 - 60, height: lineHeight)
                let pageRect = CGRect(x: pageSize.width - margin - 50, y: y, width: 50, height: lineHeight)
                drawText(title, in: textRect, font: bodyFont, alignment: .left, context: context)
                drawText("\(pageNumber)", in: pageRect, font: bodyFont, alignment: .right, context: context)
                let targetIndex = pageNumber - 1
                links.append(TOCLink(tocPageIndex: pageIndex, rect: textRect, targetPageIndex: targetIndex))
                y -= lineHeight
            }
            context.endPDFPage()
        }

        context.closePDF()
        return (PDFDocument(data: data as Data) ?? PDFDocument(), links)
    }

    private static func addTOCLinks(links: [TOCLink], to document: PDFDocument) {
        for link in links {
            let tocPage = document.page(at: link.tocPageIndex)
            let targetPage = document.page(at: link.targetPageIndex)
            guard let tocPage = tocPage, let targetPage = targetPage else {
                continue
            }
            let destination = PDFDestination(page: targetPage, at: CGPoint(x: margin, y: pageSize.height - margin))
            let annotation = PDFAnnotation(bounds: link.rect, forType: .link, withProperties: nil)
            annotation.destination = destination
            tocPage.addAnnotation(annotation)
        }
    }

    private static func addHeadersAndFooters(contentHeaders: [String], tocPages: Int, to document: PDFDocument) {
        let totalPages = document.pageCount
        for index in 0..<totalPages {
            guard let page = document.page(at: index) else {
                continue
            }
            let bounds = page.bounds(for: .mediaBox)
            let pageMargin = max(36, min(margin, bounds.width * 0.1))
            let headerTopInset = max(12, min(20, bounds.height * 0.03))
            let headerHeight: CGFloat = 16
            let headerRect = CGRect(
                x: bounds.minX + pageMargin,
                y: bounds.maxY - headerTopInset - headerHeight,
                width: bounds.width - pageMargin * 2 - 40,
                height: headerHeight
            )
            let pageNumberRect = CGRect(
                x: bounds.maxX - pageMargin - 40,
                y: bounds.maxY - headerTopInset - headerHeight,
                width: 40,
                height: headerHeight
            )
            if index >= tocPages {
                let headerText = contentHeaders[index - tocPages]
                if !headerText.isEmpty {
                    addFreeTextAnnotation(
                        to: page,
                        text: headerText,
                        in: headerRect,
                        font: NSFont.systemFont(ofSize: 9),
                        alignment: .left
                    )
                }
            }
            let pageNumber = "\(index + 1)"
            addFreeTextAnnotation(
                to: page,
                text: pageNumber,
                in: pageNumberRect,
                font: NSFont.systemFont(ofSize: 9),
                alignment: .right
            )
            let lineY = headerRect.minY - 8
            let lineRect = CGRect(
                x: bounds.minX + pageMargin,
                y: lineY,
                width: bounds.width - pageMargin * 2,
                height: 1
            )
            addLineAnnotation(to: page, in: lineRect)
        }
    }

    private static func addFreeTextAnnotation(to page: PDFPage, text: String, in rect: CGRect, font: NSFont, alignment: NSTextAlignment) {
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = font
        annotation.fontColor = NSColor.black
        annotation.color = NSColor.clear
        annotation.interiorColor = NSColor.clear
        annotation.alignment = alignment
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        page.addAnnotation(annotation)
    }

    private static func addLineAnnotation(to page: PDFPage, in rect: CGRect) {
        let annotation = PDFAnnotation(bounds: rect, forType: .line, withProperties: nil)
        annotation.color = NSColor.separatorColor
        annotation.startPoint = CGPoint(x: rect.minX, y: rect.midY)
        annotation.endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        let border = PDFBorder()
        border.lineWidth = 0.5
        annotation.border = border
        page.addAnnotation(annotation)
    }

    private static func makeHeaderText(for item: PDFItem) -> String {
        let title = item.title.isEmpty ? item.url.lastPathComponent : item.title
        if item.description.isEmpty {
            return title
        }
        return "\(title) — \(item.description)"
    }
}
