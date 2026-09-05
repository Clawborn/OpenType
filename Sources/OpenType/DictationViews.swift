import SwiftUI

/// 听写 — the redesign's version of the old History tab (handoff §3 「听写」 and
/// §6 「本地统计」).
///
/// Two things changed, and both are about what a list of past dictations is
/// *for*. It used to be one card per entry, each card repeating the mode name
/// and a relative timestamp, so a week of dictation read as a week of chrome.
/// Now one card holds a whole day and the rows inside it are separated by a
/// hairline: the card boundary means "a day", not "a row", which is the only
/// grouping a user actually scans by. And the week's own numbers moved from a
/// separate all-mode statistics area, now collapsed by default so finding
/// a recent dictation is the page's primary task (2026-09-05).
///
/// Everything here is derived. `AppModel.historyEntries` (Task 7, design
/// §3.7: the sidecar's `episodic_events` table, not the local
/// `history.json`) is the list; `UsageStats.Summary` is the band. Nothing on
/// this screen is stored for the sake of being shown.

// MARK: - The page

/// The 听写 page: header, the week's stats band, then one card per day.
///
/// Sizes itself off its own width rather than taking a `narrow` flag, so it
/// behaves the same whether the shell hands it a full content area or a
/// column — the page's layout question is "how much room do I have", and the
/// window's breakpoint is a different question with a different answer.
struct DictationColumn: View {
    @ObservedObject var model: AppModel

    @State private var query = ""
    @State private var source: String?
    @State private var showsUsage = false
    /// Pinned rather than read at every render so the bar strip's labels and
    /// the day headings do not shift underneath a user who leaves the window
    /// open across midnight without the numbers beside them moving too.
    @State private var now = Date()

    /// Below this the band drops its bar strip and folds to a grid.
    ///
    /// Four figures plus three rules plus the 190pt strip needed roughly 780pt;
    /// under 700 the figures started colliding with their own labels. D-3's
    /// fifth figure (「词典已学会」) and its rule add about 90pt to that, so the
    /// fold moves with it rather than letting the wide layout keep a width it no
    /// longer fits in. It is a property of this band's contents, not of the
    /// window, which is why it is not `DS.Size.narrowBreakpoint`.
    private static let bandFoldWidth: CGFloat = 790

    var body: some View {
        GeometryReader { proxy in
            let narrow = proxy.size.width < Self.bandFoldWidth
            let page = narrow ? DS.Space.pageNarrow : DS.Space.pageWide

            VStack(spacing: 0) {
                header(narrow: narrow)

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.group) {
                        DisclosureGroup(isExpanded: $showsUsage) {
                            UsageStatsBand(
                                summary: model.usageSummary,
                                dictionary: DictionaryStats.counts(for: model.memoryTerms),
                                narrow: narrow,
                                now: now
                            )
                            .padding(.top, 8)
                        } label: {
                            Text(OpenTypeL10n.text("使用情况 · 所有模式", english: "Usage · All modes"))
                                .font(DS.Text.caption())
                                .foregroundStyle(.secondary)
                        }

                        if dictationEntries.isEmpty {
                            // `entries.isEmpty` alone cannot tell "genuinely
                            // no history" from "the sidecar didn't answer" —
                            // that is exactly what `isConfirmedEmpty` is for
                            // (`HistoryLoadState`). An unavailable fetch must
                            // never render as "no history yet": that reads as
                            // data loss to a user whose sidecar merely hasn't
                            // answered a refresh yet.
                            if DictationHistory.isConfirmedEmpty(model.historyLoadState) {
                                emptyState(
                                    symbol: "clock.arrow.circlepath",
                                    title: OpenTypeL10n.text(
                                        "还没有听写记录",
                                        english: "No dictation yet"
                                    ),
                                    subtitle: OpenTypeL10n.text(
                                        "完成一次语音输入后会出现在这里",
                                        english: "Your first dictation will show up here"
                                    )
                                )
                            } else {
                                emptyState(
                                    symbol: "exclamationmark.triangle",
                                    title: OpenTypeL10n.text(
                                        "无法读取历史记录",
                                        english: "Couldn't load history"
                                    ),
                                    subtitle: OpenTypeL10n.text(
                                        "记录可能仍然存在，稍后会重新尝试",
                                        english: "Your history may still be there — this will retry shortly"
                                    )
                                )
                            }
                        } else if groups.isEmpty {
                            emptyState(
                                symbol: "magnifyingglass",
                                title: OpenTypeL10n.text(
                                    "没有匹配的记录",
                                    english: "Nothing matches"
                                ),
                                subtitle: OpenTypeL10n.text(
                                    "换个词，或把来源筛选改回「全部来源」",
                                    english: "Try another word, or reset the source filter"
                                )
                            )
                        } else {
                            ForEach(groups) { group in
                                DictationDayGroup(model: model, group: group)
                            }
                        }
                    }
                    .padding(.horizontal, page)
                    .padding(.bottom, page)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Recomputed on open rather than kept live: the figures cover a week, so
        // they never move while the user is looking at them except by dictating
        // — which the newest-entry watch below catches.
        .onAppear {
            now = Date()
            model.refreshUsageStats()
        }
        // 「词典已学会 N 个词」 counts rows the 记忆 page fetches; a user who has
        // never opened that page would otherwise be told the dictionary has
        // learned nothing (D-3).
        .task { await model.refreshMemoryTerms() }
        // One of the two refresh points design §3.7 calls for (the other is
        // `AppModel.recordEpisodicEvent`'s post-success refresh) — this page
        // reads the sidecar now, not a local file that was always available,
        // so opening it must actively fetch rather than trust whatever
        // `historyLoadState` happened to hold from the last time it ran.
        .task { await model.refreshHistory() }
        // Keyed on the newest entry's identity, not on `entries.count`: the
        // sidecar's episodic-events table can shrink and grow past whatever
        // count was last seen, so a count-watch would silently stop
        // refreshing for exactly the users who dictate most.
        .onChange(of: model.historyEntries.first?.id) { _ in
            now = Date()
            model.refreshUsageStats()
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(narrow: Bool) -> some View {
        // One child rather than four, because `ColumnHeader` spaces its children
        // at 8 and this header's gap is 14 (handoff 3A). Nesting the row keeps
        // the shared header's height and page padding without every other
        // column having to agree about the gap.
        ColumnHeader(narrow: narrow) {
            HStack(spacing: 14) {
                Text(AppTab.dictation.title)
                    .font(DS.Text.title())
                    .tracking(DS.Tracking.title)

                // The mockup's header is 「听写」 and the controls, nothing
                // between them. The count and 「全部保存在本机」 were an
                // addition — true, but the storage claim is already made in
                // the stats band's disclaimer right below, and the count is
                // in the sidebar badge two columns to the left. Saying it
                // three times is what made the header feel padded.
                Spacer(minLength: 0)

                searchField(narrow: narrow)
                sourceFilter
                exportMenu
            }
        }
    }

    /// Exports whatever `filtered` currently shows — the source filter and
    /// the search box both narrow it first, so exporting a search result
    /// works without a second entry point (§I, pinned decision 5 in
    /// `HistoryExportTests.swift`).
    private var exportMenu: some View {
        Menu {
            Button(OpenTypeL10n.text("导出为 Markdown", english: "Export as Markdown")) {
                export(as: .markdown)
            }
            Button(OpenTypeL10n.text("导出为 JSON", english: "Export as JSON")) {
                export(as: .json)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(DS.Text.size(15))
                .foregroundStyle(DS.Colour.ink(0.5))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .dsHeaderControl()
        .disabled(filtered.isEmpty)
        .accessibilityLabel(OpenTypeL10n.text("导出", english: "Export"))
        .help(OpenTypeL10n.text("导出当前列表为 Markdown 或 JSON", english: "Export the current list as Markdown or JSON"))
    }

    private func export(as format: HistoryExportPanel.Format) {
        let content: String
        switch format {
        case .markdown: content = HistoryExport.markdown(entries: filtered, exportedAt: Date())
        case .json: content = HistoryExport.json(entries: filtered, exportedAt: Date())
        }
        HistoryExportPanel.save(content, suggestedName: "OpenType-History", format: format)
    }

    private func searchField(narrow: Bool) -> some View {
        let placeholder = OpenTypeL10n.text("搜索转写内容", english: "Search transcripts")

        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                // 15pt, and regular rather than `DS.Text.section()`'s semibold:
                // the token's weight is for headings, and a semibold glyph reads
                // heavier than the mock's icon at the same size.
                .font(DS.Text.size(15))
                .foregroundStyle(DS.Colour.ink(0.5))
            // The placeholder is drawn rather than passed as the field's title.
            // 3A sets it at `rgba(28,28,30,.4)`, and `TextField`'s own
            // placeholder is `placeholderTextColor` — black at .25, lighter than
            // anything on the screen and the last of this header's greys still
            // resolved by the platform rather than by the handoff.
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(DS.Text.caption())
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text(placeholder)
                            .font(DS.Text.caption())
                            .foregroundStyle(DS.Colour.ink(0.4))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(placeholder)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        // .35 — the alpha 3A gives the other small glyph a user
                        // can click in this header, the source filter's
                        // indicator. Not drawn by the handoff, so it takes a
                        // step the handoff draws rather than inventing one.
                        .font(DS.Text.size(11))
                        .foregroundStyle(DS.Colour.ink(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(OpenTypeL10n.text("清除搜索", english: "Clear search"))
            }
        }
        .padding(.horizontal, 11)
        .frame(width: narrow ? 140 : 190, height: 26)
        .dsHeaderControl()
    }

    private var sourceFilter: some View {
        Menu {
            Button {
                source = nil
            } label: {
                // A leading checkmark rather than `Picker`: the menu also has to
                // carry a divider, and a `Picker` in a `Menu` renders its label
                // as a section header on macOS 13.
                Text(Self.marked(
                    OpenTypeL10n.text("全部来源", english: "All sources"),
                    selected: source == nil
                ))
            }
            if !sources.isEmpty {
                Divider()
                ForEach(sources, id: \.self) { name in
                    Button {
                        source = name
                    } label: {
                        Text(Self.marked(name, selected: source == name))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(source ?? OpenTypeL10n.text("全部来源", english: "All sources"))
                    .font(DS.Text.caption())
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    // 14pt: the mock's `unfold_more`. Off `DS.Text`'s scale
                    // because the scale sizes text, and this is a glyph sized
                    // against the 26pt control it sits in.
                    .font(DS.Text.size(14))
                    .foregroundStyle(DS.Colour.ink(0.35))
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .dsHeaderControl()
        .accessibilityLabel(OpenTypeL10n.text("来源筛选", english: "Filter by source"))
    }

    private static func marked(_ title: String, selected: Bool) -> String {
        selected ? "✓ " + title : "   " + title
    }

    // MARK: Data

    private var dictationEntries: [HistoryEntry] {
        DictationHistory.entries(in: model.historyEntries)
    }

    /// Every source app that has produced an entry, so the filter offers only
    /// choices that can return something.
    private var sources: [String] {
        var seen = Set<String>()
        return dictationEntries
            .map(\.applicationName)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
    }

    /// Source filter narrows first, then `HistorySearch` matches the body —
    /// transcript, result and application name, ANDed term by term rather
    /// than a single-needle contains. See `HistorySearch` for why: a query
    /// matching the body but not an auto-generated title is the entire point
    /// of §I, and this is also what feeds the `…` menu's export, so
    /// "export" means "export what I am looking at".
    private var filtered: [HistoryEntry] {
        let bySource = source.map { source in
            dictationEntries.filter { $0.applicationName == source }
        } ?? dictationEntries
        return HistorySearch.filter(bySource, query: query)
    }

    private var displayedCount: Int { filtered.count }

    /// `filtered`, cut into calendar days, newest day first. `GET
    /// /memory/events` already returns newest-first, so the rows inside a
    /// day keep that order without a second sort.
    private var groups: [DictationDay] {
        var order: [Date] = []
        var buckets: [Date: [HistoryEntry]] = [:]
        let calendar = Calendar.current

        for entry in filtered {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(entry)
        }

        return order.map { day in
            DictationDay(id: day, title: Self.dayTitle(day), entries: buckets[day] ?? [])
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return OpenTypeL10n.text("今天", english: "Today")
        }
        if calendar.isDateInYesterday(day) {
            return OpenTypeL10n.text("昨天", english: "Yesterday")
        }
        return DictationFormat.day.string(from: day)
    }

    // MARK: Empty

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(DS.Text.title())
                // .3 and .45: the handoff has no empty state to copy, so the
                // two lines take the alphas it gives the same two roles
                // elsewhere — .3 is what 06C dims an absent figure to, .45 is
                // every row subtitle on 03A and 03C.
                .foregroundStyle(DS.Colour.ink(0.3))
            Text(title)
                .font(DS.Text.body(.semibold))
            Text(subtitle)
                .font(DS.Text.caption())
                .foregroundStyle(DS.Colour.ink(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// One calendar day's worth of dictations.
private struct DictationDay: Identifiable {
    let id: Date
    let title: String
    let entries: [HistoryEntry]
}

// MARK: - A day

/// A group label and the single card that holds that day's rows.
///
/// One card, N rows, hairlines between — not N cards. A card edge that means
/// "row" spends a shadow, a border and 8pt of gap on a boundary the user gets
/// for free from the line of text itself.
private struct DictationDayGroup: View {
    @ObservedObject var model: AppModel
    let group: DictationDay

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.label) {
            Text(group.title)
                .font(DS.Text.groupLabel())
                .tracking(DS.Tracking.groupLabel)
                .foregroundStyle(DS.Colour.ink(0.42))
                .padding(.horizontal, DS.Space.labelInset)

            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    if index == 0 {
                        DictationRow(model: model, entry: entry)
                    } else {
                        // Between rows only. A hairline above the first row
                        // would read as a second card edge 0.75pt inside the
                        // real one.
                        DictationRow(model: model, entry: entry)
                            .dsHairline(.top)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .dsCard()
        }
    }
}

/// One dictation: when and where on the left, what was said in the middle,
/// what you can do with it on the right.
///
/// The left column is fixed at 64pt so the transcripts start on the same x in
/// every row — a ragged left edge on the one column the eye reads down is what
/// made the old list feel like a pile.
private struct DictationRow: View {
    @ObservedObject var model: AppModel
    let entry: HistoryEntry

    @State private var hovering = false
    @State private var showingDeleteConfirmation = false

    /// `entry.result` is optional as of Task 7 — a row can be recorded
    /// without ever having delivered anything. The transcript is the closest
    /// available stand-in for "what this row was about", the same fallback
    /// `AppModel.reuse(_:)` uses for the same case.
    private var displayText: String { entry.result ?? entry.transcript }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.content) {
            VStack(alignment: .leading, spacing: 3) {
                Text(DictationFormat.time.string(from: entry.createdAt))
                    .font(DS.Text.mono())
                    .foregroundStyle(DS.Colour.ink(0.45))
                Text(entry.applicationName)
                    .font(DS.Text.size(11))
                    .foregroundStyle(DS.Colour.ink(0.35))
                    .lineLimit(1)
            }
            .frame(width: 64, alignment: .leading)
            .padding(.top, 1)

            Text(displayText)
                .font(DS.Text.body())
                // 13pt at a 1.6 line box: SwiftUI's `lineSpacing` is the extra
                // gap, not the box, so ~5 rather than ~21.
                .lineSpacing(5)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                DictationRowAction(
                    symbol: "doc.on.doc",
                    label: OpenTypeL10n.text("复制", english: "Copy"),
                    rowHovering: hovering
                ) {
                    model.copy(displayText)
                }
                DictationRowAction(
                    symbol: "arrow.counterclockwise",
                    label: OpenTypeL10n.text("重新使用", english: "Re-use"),
                    rowHovering: hovering
                ) {
                    model.reuse(entry)
                }
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, DS.Space.content)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The remedy §I adds: say one sensitive thing by accident and this is
        // the way out, without wiping the rest of the history to get it.
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(OpenTypeL10n.text("删除", english: "Delete"), systemImage: "trash")
            }
        }
        .confirmationDialog(
            OpenTypeL10n.text("删除这条记录？", english: "Delete this entry?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(OpenTypeL10n.text("确认删除", english: "Delete"), role: .destructive) {
                Task { await model.deleteHistoryEntry(id: entry.id) }
            }
        } message: {
            Text(OpenTypeL10n.text("删除后无法恢复。", english: "This cannot be undone."))
        }
    }
}

/// A row action.
///
/// Present in every row rather than revealed on hover — the handoff draws both
/// glyphs in the resting row and specifies the hover as a *darkening* (`.32` →
/// `.55`), not an appearance. That distinction is deliberate on its side: the
/// 记忆 page's edit/delete actions are the ones spelled 「改为 hover 出现，不常驻」,
/// and these are not. A user scanning a week of transcripts can see that a row
/// is copyable without discovering it with the pointer.
private struct DictationRowAction: View {
    let symbol: String
    let label: String
    /// Darkens with the row, not with the glyph: the handoff's hover state is a
    /// property of the row, so both icons answer together.
    let rowHovering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                // 16pt regular. `DS.Text.section()` is 15pt semibold — the wrong
                // size and the wrong weight for a glyph, and it was reading as a
                // heading-sized mark next to 13pt body.
                .font(DS.Text.size(16))
                .foregroundStyle(rowHovering ? DS.Colour.accent : DS.Colour.ink(0.6))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - The stats band

/// 最近 7 天, as the 听写 page's own header (handoff §6).
///
/// Four figures and a bar strip, all of it recomputed from
/// `audit-events.v1.jsonl` at read time. Only the fourth figure is coloured,
/// and that is the whole editorial position of the band: 每 100 字纠错 is the
/// one number that is *supposed* to move — it should fall as the entity
/// dictionary learns what this user says — while the other three describe. If
/// all four were accented, none of them would be the one to watch.
struct UsageStatsBand: View {
    let summary: UsageStats.Summary
    /// 「词典已学会 N 个词」 (D-3) — counted over `AppModel.memoryTerms`, the rows
    /// the 记忆 page already fetches. The band's one figure that is not derived
    /// from the audit trail, and the one that means something on day three,
    /// before a week of history exists for the trend line to have a slope.
    let dictionary: DictionaryStats.LearnedTermCounts
    let narrow: Bool
    /// Injected so the bar labels are stable across re-renders and testable
    /// without waiting for a real midnight.
    var now: Date = Date()

    /// The 34pt the tallest bar gets.
    private static let barHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            if narrow {
                narrowBody
            } else {
                wideBody
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .dsCard()
    }

    // MARK: Wide

    private var wideBody: some View {
        HStack(alignment: .top, spacing: DS.Space.pageWide) {
            HStack(alignment: .top, spacing: 28) {
                figure(words)
                rule
                figure(endToEnd)
                rule
                figure(response)
                rule
                figure(rate)
                rule
                figure(learned)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            barStrip
                .frame(width: 190)
        }
        .padding(.horizontal, 20)
        .padding(.top, DS.Space.content)
        .padding(.bottom, 14)
    }

    private var rule: some View {
        Rectangle()
            .fill(DS.Colour.border)
            .frame(width: 0.75)
            .frame(maxHeight: .infinity)
    }

    // MARK: Narrow

    private var narrowBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                weekLabel
                Spacer(minLength: 0)
                deliveriesLabel
            }
            .padding(.horizontal, DS.Space.content)
            .padding(.top, 12)
            .padding(.bottom, 10)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20, alignment: .leading),
                    GridItem(.flexible(), spacing: 20, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 14
            ) {
                // The bar strip, the week-over-week trend and D-3's seven-point
                // line all go: at this width a 7-bar strip is 7 slivers and a
                // 7-point line is a squiggle, and both are the parts of a figure
                // that can be dropped without the figure itself stopping making
                // sense. The numbers all stay.
                ForEach([words, endToEnd, response, rate, learned]) { item in
                    compactFigure(item)
                }
            }
            .padding(.horizontal, DS.Space.content)
            .padding(.bottom, 14)
        }
    }

    // MARK: Figures

    private func figure(_ item: Figure) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                value(item, wide: true)
                if let trend = item.trend {
                    HStack(spacing: 2) {
                        Image(systemName: trend.symbol)
                            .font(DS.Text.body())
                        Text(trend.label)
                            .font(DS.Text.mono())
                    }
                    .foregroundStyle(DS.Colour.ink(0.42))
                }
            }
            // The whole point of D-3: the number above is where this week
            // landed, and the line is whether it is falling. Drawn between the
            // value and its label so it reads as part of the figure rather than
            // as a chart parked next to it.
            if let series = item.series {
                CorrectionTrendLine(values: series)
                    .frame(width: Self.trendWidth, height: Self.trendHeight)
                    .padding(.top, 2)
                    .padding(.bottom, 1)
            }
            Text(item.label)
                .font(DS.Text.caption().weight(.medium))
                .foregroundStyle(item.hasData ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.Colour.ink(0.5)))
                .fixedSize(horizontal: false, vertical: true)
            if let note = item.note {
                Text(note)
                    .font(DS.Text.size(11))
                    .foregroundStyle(DS.Colour.ink(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Natural width, not an equal share of the row. The mock packs the four
        // figures at the left of a `flex:1` container with exactly 28pt between
        // them and leaves the slack on the right; splitting the row four ways
        // instead puts a different, wider gap after each figure, which is the
        // one thing a set of separated figures must not have.
    }

    private func compactFigure(_ item: Figure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value(item, wide: false)
            Text(item.label)
                // 11.5 in 06B, against the wide band's 12/500. The narrow card
                // is 394pt and the label has to survive 「每 100 字纠错」 in one
                // line; the half point is the handoff's answer to that.
                .font(DS.Text.size(11.5))
                .foregroundStyle(item.hasData ? AnyShapeStyle(.primary) : AnyShapeStyle(DS.Colour.ink(0.5)))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The number, and 「秒」 riding on it.
    ///
    /// The two variants differ by more than the point size, which is why this
    /// takes `wide` rather than a size: the handoff tracks the 26pt figure at
    /// `-.02em` and the 22pt one not at all, and sets the unit at 15pt with 2pt
    /// of lead in the band against 13pt flush in the grid.
    private func value(_ item: Figure, wide: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(item.value)
                .font(DS.Text.mono(wide ? 26 : 22, weight: .semibold))
                // Resolved against this step rather than reusing
                // `DS.Tracking.title`, which is the same `-.02em` already
                // resolved at 20pt and so 0.12pt short at 26.
                .tracking(wide ? DS.Tracking.em(-0.02, at: 26) : 0)
                .foregroundStyle(item.valueStyle)
            if let unit = item.unit {
                Text(unit)
                    // Medium, not `DS.Text.section()`'s semibold: the handoff
                    // draws the unit a weight lighter than the number so it
                    // reads as prose. The .45 ink carries the same demotion.
                    .font(wide ? DS.Text.section().weight(.medium) : DS.Text.body(.medium))
                    .foregroundStyle(DS.Colour.ink(0.45))
                    .padding(.leading, wide ? 2 : 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label) \(item.value)\(item.unit ?? "")")
    }

    // MARK: Bars

    private var weekLabel: some View {
        Text(OpenTypeL10n.text("最近 7 天", english: "Last 7 days"))
            .font(DS.Text.groupLabel())
            .tracking(DS.Tracking.groupLabel)
            .foregroundStyle(DS.Colour.ink(0.42))
    }

    private var deliveriesLabel: some View {
        Text(OpenTypeL10n.text(
            "\(summary.deliveries) 次交付",
            english: "\(summary.deliveries) deliveries"
        ))
        .font(DS.Text.mono())
        .foregroundStyle(DS.Colour.ink(0.4))
    }

    private var barStrip: some View {
        let peak = max(summary.dailyWords.max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                weekLabel
                Spacer(minLength: 0)
                deliveriesLabel
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(summary.dailyWords.enumerated()), id: \.offset) { index, count in
                    bar(index: index, count: count, peak: peak)
                }
            }
        }
    }

    private func bar(index: Int, count: Int, peak: Int) -> some View {
        // Rolling 24-hour buckets, oldest first: bar `i` covers the day ending
        // `(6 - i) * 86400` seconds ago. Not calendar days — `UsageStats` buckets
        // this way so the strip sums to the printed word total exactly.
        let day = now.addingTimeInterval(-Double(UsageStats.bucketCount - 1 - index) * 86_400)
        let isToday = index == summary.dailyWords.count - 1
        let height = count > 0
            ? max(2, Self.barHeight * CGFloat(count) / CGFloat(peak))
            : 0

        return VStack(spacing: 5) {
            // No baseline rule under the bars: the handoff draws the column as
            // an empty 34pt box with the bar sitting in the bottom of it, and a
            // hairline across all seven adds an axis the design does not have.
            ZStack(alignment: .bottom) {
                UnevenRoundedTop(radius: 3)
                    .fill(DS.Colour.accent.opacity(0.55))
                    .frame(height: height)
            }
            .frame(height: Self.barHeight)
            .frame(maxWidth: .infinity)

            // Seven weekday letters in one neutral colour. The last bucket is
            // the day the user is standing in and so is always short — but that
            // belongs in the tooltip below, not in a second blue on a band whose
            // whole point is that 每 100 字纠错 owns the only accent.
            Text(DictationFormat.weekday.string(from: day))
                .font(DS.Text.mono(10))
                .foregroundStyle(DS.Colour.ink(0.35))
                .lineLimit(1)
        }
        .help(isToday
              ? OpenTypeL10n.text(
                  "今天 · \(count) 字（当天还没过完）",
                  english: "Today · \(count) words (the day is still in progress)"
              )
              : OpenTypeL10n.text(
                  "\(DictationFormat.day.string(from: day)) · \(count) 字",
                  english: "\(DictationFormat.day.string(from: day)) · \(count) words"
              ))
    }

    // MARK: The four figures

    /// The 7-point line's box. Narrow enough to sit inside a figure's own
    /// column rather than widening the row, tall enough that a real change of
    /// slope is visible at a glance.
    private static let trendWidth: CGFloat = 96
    private static let trendHeight: CGFloat = 22

    private struct Figure: Identifiable {
        let id: String
        let value: String
        /// 「秒」, set apart because it is prose riding on a number.
        var unit: String?
        let label: String
        /// `nil` when there is nothing data-bearing to say — the owner copy
        /// rule (§5) removed the standing methodology lectures ("CJK by
        /// character · Latin by word", the generic "key release → delivered
        /// text" placeholder, "should fall as the dictionary learns") that
        /// used to fill this line unconditionally; what is left only prints
        /// when it folds in an actual value (see `endToEndNote`) or an
        /// owner-share count (see `learned`).
        let note: String?
        /// `false` when the figure printed 「—」 or a dimmed zero. Drives the
        /// value's colour, and demotes the label with it.
        let hasData: Bool
        var accented = false
        var trend: Trend?
        /// Seven days of this figure, oldest first, drawn as a line under the
        /// number (D-3). `nil` for the figures that are not a series.
        var series: [Double?]?

        var valueStyle: AnyShapeStyle {
            // 06C prints an unmeasurable figure at .3, and explicitly does not
            // let the accent through — a dimmed 「—」 in blue would read as a
            // value rather than as an absence.
            if !hasData { return AnyShapeStyle(DS.Colour.ink(0.3)) }
            return accented ? AnyShapeStyle(DS.Colour.accent) : AnyShapeStyle(.primary)
        }
    }

    private struct Trend {
        let symbol: String
        let label: String
    }

    private var words: Figure {
        Figure(
            id: "words",
            // The one figure that prints a real `0` rather than 「—」: a week
            // that dictated nothing is a fact, where an unmeasurable latency is
            // an absence. Dimmed so the two still read differently.
            value: Self.grouped(summary.wordsDictated),
            label: OpenTypeL10n.text("说出的字数", english: "Words dictated"),
            note: nil,
            hasData: summary.wordsDictated > 0
        )
    }

    private var endToEnd: Figure {
        Figure(
            id: "endToEnd",
            value: Self.latencyValue(summary.averageEndToEndLatency),
            unit: summary.averageEndToEndLatency == nil ? nil : Self.secondsUnit,
            label: OpenTypeL10n.text("平均等待", english: "Average wait"),
            note: endToEndNote,
            hasData: summary.averageEndToEndLatency != nil
        )
    }

    /// 「松开快捷键 → 出字」, broken into per-mode figures when there is more
    /// than one mode's worth of data behind the headline this week (see (c)
    /// in `UsageStatsPerModeLatencyTests`) — named only for the modes that
    /// actually delivered something, so a dictation-only week and a
    /// questions-only week each print one plain figure instead of a lopsided
    /// 「·」 pointing at a mode with nothing behind it. This is a fifth number
    /// riding on an existing figure's `note` line rather than a fifth
    /// `Figure`, on purpose — the panel's layout is closed at four.
    ///
    /// `nil` when neither per-mode figure has data — the headline can still
    /// be non-`nil` in that case (a legacy pre-3-mode-era row, or a
    /// `transcribe`/`ask` session missing `recognized.recordingEndedAt`, both
    /// still counted toward the headline but attributed to neither column),
    /// and there is no per-mode value left to show. This used to fall back to
    /// a standing "key release → delivered text" placeholder sentence; the
    /// owner copy rule (§5) removed it since it named no actual data.
    private var endToEndNote: String? {
        switch (summary.averageTranscribeEndToEndLatency, summary.averageAskEndToEndLatency) {
        case let (transcribe?, ask?):
            return OpenTypeL10n.text(
                "听写 \(Self.latencyValue(transcribe))秒 · 问答 \(Self.latencyValue(ask))秒",
                english: "Transcribe \(Self.latencyValue(transcribe))s · Ask \(Self.latencyValue(ask))s"
            )
        case let (transcribe?, nil):
            return OpenTypeL10n.text(
                "听写 \(Self.latencyValue(transcribe))秒",
                english: "Transcribe \(Self.latencyValue(transcribe))s"
            )
        case let (nil, ask?):
            return OpenTypeL10n.text(
                "问答 \(Self.latencyValue(ask))秒",
                english: "Ask \(Self.latencyValue(ask))s"
            )
        case (nil, nil):
            return nil
        }
    }

    private var response: Figure {
        Figure(
            id: "response",
            value: Self.latencyValue(summary.averageResponseLatency),
            unit: summary.averageResponseLatency == nil ? nil : Self.secondsUnit,
            label: OpenTypeL10n.text("回答耗时", english: "Response time"),
            note: nil,
            hasData: summary.averageResponseLatency != nil
        )
    }

    private var rate: Figure {
        let hasData = summary.wordsDictated > 0
        return Figure(
            id: "rate",
            // 「—」 rather than 「0.0」 when nothing was dictated: `Summary`
            // reports the rate as 0 in that case, and 「0.0」 under 每 100 字纠错
            // beside 「0 字」 reads as a perfect score rather than an empty week.
            value: hasData
                ? String(format: "%.1f", summary.correctionsPerHundredWords)
                : "—",
            label: OpenTypeL10n.text("每 100 字纠错", english: "Corrections per 100 words"),
            note: nil,
            hasData: hasData,
            accented: true,
            trend: trend(hasData: hasData),
            // Only in the wide band: `narrowBody` draws figures without their
            // series, and a 96pt line squeezed into a 394pt two-column grid
            // would be a squiggle nobody can read a slope off.
            series: narrow ? nil : summary.dailyCorrectionsPerHundredWords
        )
    }

    /// 「词典已学会 N 个词」 — what the loop has actually learned, as opposed to
    /// whether it is helping yet.
    private var learned: Figure {
        Figure(
            id: "learned",
            value: Self.grouped(dictionary.total),
            label: OpenTypeL10n.text("词典已学会", english: "Terms learned"),
            // The owner's share, separately, because `remember_fact` can write
            // terms out of agent context (P1-12) and a blended count would let a
            // number the user reads as 「what I have taught it」 quietly include
            // rows nobody taught it.
            note: dictionary.total == 0
                ? OpenTypeL10n.text("纠错一次就会记住", english: "One correction teaches it one")
                : OpenTypeL10n.text(
                    "其中 \(dictionary.owner) 个来自你",
                    english: "\(dictionary.owner) taught by you"
                ),
            hasData: dictionary.total > 0
        )
    }

    /// 「上周 N」, with the arrow pointing the way the number actually went.
    ///
    /// The handoff draws `arrow.down`, because down is the direction this
    /// metric is supposed to move. Drawing it unconditionally would print a
    /// falling arrow beside a rising number, so the glyph follows the
    /// comparison and the intent survives: down still means "better".
    private func trend(hasData: Bool) -> Trend? {
        guard hasData, let previous = summary.previousCorrectionsPerHundredWords else {
            return nil
        }
        let current = summary.correctionsPerHundredWords
        let symbol: String
        if current < previous {
            symbol = "arrow.down"
        } else if current > previous {
            symbol = "arrow.up"
        } else {
            symbol = "minus"
        }
        return Trend(
            symbol: symbol,
            label: OpenTypeL10n.text(
                String(format: "上周 %.1f", previous),
                english: String(format: "last week %.1f", previous)
            )
        )
    }

    // MARK: Formatting

    private static let secondsUnit = OpenTypeL10n.text("秒", english: "s")

    /// 「—」 for an absent measurement, never 「0.0」: a week whose sessions all
    /// predate `ImmutableAuditEvent.recordingEndedAt` has nothing to report, and
    /// 「0.0 秒」 would read as "instant".
    private static func latencyValue(_ latency: TimeInterval?) -> String {
        guard let latency else { return "—" }
        return String(format: "%.1f", latency)
    }

    private static func grouped(_ value: Int) -> String {
        DictationFormat.count.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - The convergence line

/// Seven days of 每 100 字纠错, drawn as a line (D-3).
///
/// The band already printed this week's rate and 「上周 N」 beside it, which is
/// the weakest possible way to show a slope: two numbers a week apart cannot
/// tell 「the dictionary is learning」 from 「I happened to talk less」. A line
/// over the same seven buckets the bar strip uses can.
///
/// Drawn with `Path` rather than a charting dependency, per §D-3: seven points
/// need no framework, and one would arrive with its own type scale, its own
/// colours and its own idea of what an axis looks like — none of which are
/// `DS`'s.
///
/// **A gap is not a zero.** `UsageStats` reports `nil` for a day that delivered
/// nothing and a real `0` for a day that delivered and needed no corrections,
/// and those two must not look alike: the second is the best day the product can
/// have. So the line breaks across gaps, and a day that stands alone between two
/// gaps is drawn as a dot — a single point has no segment, and dropping it would
/// hide the only measurement a new user has.
private struct CorrectionTrendLine: View {
    let values: [Double?]

    /// Dot radius for an isolated day, and the width of the line itself.
    private static let dotRadius: CGFloat = 1.6
    private static let lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                // The baseline is what makes a falling line read as falling
                // *towards* something rather than merely sloping. Drawn at the
                // bottom of the box, which is where a rate of zero lands.
                Rectangle()
                    .fill(DS.Colour.border)
                    .frame(height: 0.75)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                ForEach(Array(runs(of: points).enumerated()), id: \.offset) { _, run in
                    if run.count == 1, let only = run.first {
                        Circle()
                            .fill(DS.Colour.accent)
                            .frame(
                                width: Self.dotRadius * 2,
                                height: Self.dotRadius * 2
                            )
                            .position(only.point)
                    } else {
                        path(through: run.map(\.point))
                            .stroke(
                                DS.Colour.accent,
                                style: StrokeStyle(
                                    lineWidth: Self.lineWidth,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(OpenTypeL10n.text(
            "最近 7 天每 100 字纠错趋势",
            english: "Corrections per 100 words over the last 7 days"
        ))
    }

    /// Where each measured day sits in the box. Days with no data have no point
    /// at all, which is what produces the gaps.
    ///
    /// The scale is fixed at the week's own peak rather than at a constant, so a
    /// week that improved from 6 to 1 and a week that improved from 0.6 to 0.1
    /// both fill the box — the shape is the message, and the number above it is
    /// the magnitude. `max(peak, …)` keeps a flat week of small values off the
    /// baseline instead of drawing it as a line of zeroes.
    private func points(in size: CGSize) -> [(index: Int, point: CGPoint)] {
        let measured = values.compactMap { $0 }
        guard !measured.isEmpty else { return [] }
        let peak = max(measured.max() ?? 0, 0.0001)
        let steps = max(values.count - 1, 1)
        let inset = Self.dotRadius + Self.lineWidth / 2

        return values.enumerated().compactMap { index, value in
            guard let value else { return nil }
            let x = size.width * CGFloat(index) / CGFloat(steps)
            let usable = max(size.height - inset * 2, 1)
            let y = size.height - inset - usable * CGFloat(value / peak)
            return (
                index,
                CGPoint(
                    x: min(max(x, inset), max(size.width - inset, inset)),
                    y: y
                )
            )
        }
    }

    /// Consecutive measured days, split wherever a day is missing.
    private func runs(
        of points: [(index: Int, point: CGPoint)]
    ) -> [[(index: Int, point: CGPoint)]] {
        var runs: [[(index: Int, point: CGPoint)]] = []
        for entry in points {
            if let last = runs.last?.last, last.index == entry.index - 1 {
                runs[runs.count - 1].append(entry)
            } else {
                runs.append([entry])
            }
        }
        return runs
    }

    private func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

// MARK: - Shapes

/// A bar with its top two corners rounded, per the handoff's `3 3 0 0`.
///
/// Hand-drawn because `UnevenRoundedRectangle` is macOS 14 and this target is
/// 13 — and because the radius has to shrink with the bar: a day worth 2pt
/// rounded at 3pt is a lozenge, not a bar, and the strip's shortest days are
/// exactly the ones a reader is trying to compare.
private struct UnevenRoundedTop: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.height, rect.width / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Header control chrome

private extension View {
    /// The 26pt white pill the header's search field and source filter share:
    /// r7, a `rgba(0,0,0,.09)` edge, the control lift.
    ///
    /// 7 and .09, not the 6 and .07 an earlier pass rounded them to. A header
    /// control sits on `#F5F5F3` rather than inside a card, so it has almost no
    /// value contrast to rest on — the extra point of radius and the two
    /// hundredths of alpha are what the handoff spends on making it read as a
    /// control at all.
    func dsHeaderControl() -> some View {
        DS.Shadow.control(
            background(
                DS.Colour.card,
                in: RoundedRectangle(cornerRadius: DS.Radius.smallControl, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.smallControl, style: .continuous)
                    .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
            )
        )
    }
}

// MARK: - Formatters

/// Built once. `DateFormatter` construction is expensive enough that doing it
/// per row shows up in a list of 100.
private enum DictationFormat {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 「8月13日」 in zh-Hans, 「Aug 13」 in English — from a template rather than
    /// a hardcoded pattern, so the order and separators follow the locale.
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// The single-character weekday under each bar.
    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    /// 「4,182」 — grouped, because the figure it sets is the one users read as
    /// a magnitude rather than a value.
    static let count: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
