import SwiftUI

/// The redesign's type, shape, colour and spacing scale (2026-08 handoff,
/// `design_handoff_opentype_redesign_v1`).
///
/// **These are the mockup's own values, not a six-step abstraction over them.**
/// An earlier pass implemented the README's closed scale — six type sizes, four
/// radii, one border — and collapsed everything the markup drew between those
/// steps. The owner reversed that on 2026-08-15: 稿子优先, the mockup wins
/// unconditionally where the two disagree. So the steps below are wider than
/// the README describes, and that is deliberate; the README's scale section is
/// the document that is now out of date, and `docs/reviews/` records the
/// contradiction for the design side.
///
/// The file still exists for the reason it always did: values live here under
/// names, once, instead of as literals sprinkled through six view files. What
/// changed is only how many steps there are, not whether they are shared.
///
/// Everything here is a value from the handoff, not an interpretation of it.
/// Deviations belong in a comment saying why, not in a quietly different
/// number.
///
/// Two consequences of 稿子优先 that are easy to undo by accident:
///
/// - **Colours are literal, not semantic.** The app is pinned to the light
///   appearance (`OpenTypeApp`), and the handoff's values are absolute — its
///   contrast is computed against `#fff` and `rgba(0,0,0,α)`, not against
///   whatever the system decides a separator is. `Color.primary.opacity(0.07)`
///   is *not* `rgba(0,0,0,.07)`: `labelColor` is black at 0.85, so that
///   expression resolves to 0.0595. Borders and ink below are therefore built
///   from literal black and literal `#1C1C1E`.
/// - **Ink is its own axis.** SwiftUI's hierarchical styles offer three usable
///   levels (≈ .85 / .50 / .26). The handoff uses a dozen, and most of them sit
///   in the `.30–.45` band the hierarchical styles skip entirely — which is
///   where every group label, timestamp, figure note and row action lives.
///   `DS.Colour.ink(_:)` is that axis; `.tertiary` is not a substitute for it.
enum DS {

    // MARK: - Type

    /// Every SF size the handoff sets, at the weights it sets them.
    ///
    /// The named members are the sizes that recur across screens; `size(_:_:)`
    /// reaches the rest. The half-point steps are real and deliberate: `10.5 /
    /// 11.5 / 12.5 / 13.5` appear on five of the six screens, and they are what
    /// the handoff reaches for when something is *slightly* smaller or larger
    /// than body — a row subtitle, an inline text action, an answer.
    enum Text {
        /// 20 / 700 — page titles (会话 / 听写 / 记忆 / 设置).
        static func title() -> Font { .system(size: 20, weight: .bold) }
        /// 15 / 600 — section headings, and headings inside an answer.
        static func section() -> Font { .system(size: 15, weight: .semibold) }
        /// 13 — body, and the main line of a list row.
        static func body(_ weight: Font.Weight = .regular) -> Font {
            .system(size: 13, weight: weight)
        }
        /// 12 — secondary explanation. Pair with `ink(0.5)` or lighter.
        static func caption() -> Font { .system(size: 12) }
        /// 11 / 600 — group labels (今天 / 进行中 / 内置工具). Pair with
        /// `ink(0.42)`, which is the α the handoff sets on every one of them.
        static func groupLabel() -> Font { .system(size: 11, weight: .semibold) }
        /// Half-steps the mockup uses between the README's named sizes. Named
        /// rather than passed as literals so a later reader can see the set.
        ///
        /// In use: `10.5` (badges, type tags), `11` regular (figure notes, app
        /// names, disclaimers) and `11` medium (small inline actions), `11.5`
        /// (inline text actions, row subtitles, narrow figure labels), `12.5`
        /// (panel body copy, card titles), `13.5` (an answer's body), `14`
        /// semibold (a thread title), `15` medium (the live caption).
        static func size(_ points: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: points, weight: weight)
        }
        /// Every machine-produced string.
        ///
        /// The scope is deliberately narrow and worth naming, because the
        /// failure is asymmetric: timestamps, durations, counts, tool names,
        /// paths, commands, server names, masked secrets and confidence
        /// percentages all read better aligned — and Chinese body text set in a
        /// monospaced face reads as a terminal dump. Never use this on prose.
        static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// The tracking the handoff specifies, resolved to points.
    enum Tracking {
        static let title: CGFloat = -0.4      // -.02em at 20pt
        static let groupLabel: CGFloat = 0.55 // .05em at 11pt
        static let brand: CGFloat = -0.13     // -.01em at 13pt, the wordmark

        /// The handoff writes tracking in em; SwiftUI takes points, and the
        /// conversion depends on the size it lands at — `-.02em` is −0.4 at
        /// 20pt and −0.52 at 26pt. Resolving it here is what stops the 20pt
        /// answer being reused at 26 because it was the constant that existed.
        static func em(_ value: CGFloat, at size: CGFloat) -> CGFloat { value * size }
    }

    // MARK: - Shape

    /// The radii the mockup actually draws.
    enum Radius {
        /// Controls: buttons, filter chips, segmented controls, dropdowns, tags.
        static let control: CGFloat = 6
        /// Blocks nested inside a card; icon buttons; progress containers.
        static let inset: CGFloat = 10
        /// Cards: list containers, settings groups, the stats band.
        static let card: CGFloat = 14
        /// Floating panels.
        static let panel: CGFloat = 18

        // Steps the markup uses between those four. Present because the mockup
        // is the authority, not because each earns its own concept.
        static let tag: CGFloat = 5
        static let chip: CGFloat = 4
        static let smallControl: CGFloat = 7
        static let block: CGFloat = 8
        static let nested: CGFloat = 9
        static let sheet: CGFloat = 13
        static let pill: CGFloat = 99
    }

    // MARK: - Colour

    /// One accent, and colour reserved for things that need an action.
    ///
    /// The rule that changes the most on screen: **success is no longer
    /// green.** Success is the common case, and colouring the common case
    /// spends the user's attention on the outcome they expected. A neutral row
    /// with a `checkmark` says the same thing and leaves colour meaning
    /// "something wants you".
    enum Colour {
        /// `#0D73FA`. The only accent. Already `AppAccent.primary`; aliased
        /// rather than redefined so there is still one definition.
        static let accent = AppAccent.primary
        /// `#4B45E8` — agent identity: type tags and tool names in a step log,
        /// nothing else.
        static let agent = Color(red: 0.294, green: 0.271, blue: 0.910)
        /// `#5751FA` — the end stop of the brand mark's `135deg` gradient. Not
        /// an identity colour; it exists so the mark is not drawn from `accent`
        /// to `agent`, which would make the app's own icon say "Agent".
        static let brandGradientEnd = Color(red: 0.341, green: 0.318, blue: 0.980)

        /// Neutral surfaces, owner-approved native direction (2026-09-05).
        static let canvas = Color(red: 0.969, green: 0.969, blue: 0.976)
        /// Slightly darker than `canvas`, which is what separates the sidebar
        /// from the list without a border between them.
        static let sidebar = Color(red: 0.945, green: 0.945, blue: 0.953)
        /// Literal white rather than `.textBackgroundColor`. The app is pinned
        /// to the light appearance (`OpenTypeApp`), so the two agree today —
        /// but a semantic colour here would silently reintroduce the dark
        /// palette the moment that pin is lifted, and the design's contrast
        /// ratios are computed against this value, not against whatever the
        /// system decides a text background is.
        static let card = Color.white

        // MARK: Fills — `rgba(0,0,0,α)`

        /// `rgba(0,0,0,.035)` — a recessed block over a blurred material, which
        /// is the only place the handoff writes this as an α rather than as the
        /// `#FAFAF8` below.
        static let inset = Color.black.opacity(0.035)
        /// `rgba(0,0,0,.045)` — inline code chips, tool chips.
        static let codeFill = Color.black.opacity(0.045)
        /// `rgba(0,0,0,.05)` — an unselected chip or mode cell, a neutral badge.
        static let control = Color.black.opacity(0.05)
        /// `rgba(0,0,0,.055)` — 会话's unselected filter chip. Half a percent
        /// from `control` and both are drawn; kept apart so neither screen has
        /// to claim the other's value.
        static let chipFill = Color.black.opacity(0.055)

        // MARK: Borders — `rgba(0,0,0,α)`, all 0.75pt

        /// The README claims a single global border value. The markup disagrees
        /// with it on roughly forty elements, and under 稿子优先 the markup
        /// wins, so there are seven. They are ordered lightest to heaviest and
        /// the ordering is the meaning: the further inside a surface a line is,
        /// the lighter it is drawn.
        ///
        /// `.06` — between rows inside one card.
        static let hairline = Color.black.opacity(0.06)
        /// `.07` — a card's own edge, and where one region of a window ends and
        /// another begins (a header's bottom, a composer's top).
        static let border = Color.black.opacity(0.07)
        /// `.08` — a composer's container, a progress track, a step-log summary
        /// sitting on a panel.
        static let borderStrong = Color.black.opacity(0.08)
        /// `.09` — a lifted small control: header icon buttons, search fields,
        /// the composer's mic button, an option list.
        static let controlBorder = Color.black.opacity(0.09)
        /// `.1` — a container block inside a sheet.
        static let blockBorder = Color.black.opacity(0.10)
        /// `.12` — a bordered button (授权 / 取消 / 重新测试 / 复制成我的配置).
        static let buttonBorder = Color.black.opacity(0.12)
        /// `.14` — a text field's edge, and a toggle's off track. The heaviest
        /// line in the design.
        static let fieldBorder = Color.black.opacity(0.14)

        // MARK: Ink — `rgba(28,28,30,α)`

        /// 文字主 `#1C1C1E`, opaque. `.primary` is the usual way to reach it —
        /// this is here so `ink(_:)` below has a literal base, and for the rare
        /// caller that needs the exact colour rather than the label style.
        static let inkBase = Color(red: 0.110, green: 0.110, blue: 0.118)

        /// Secondary text at the handoff's own α.
        ///
        /// Literal `#1C1C1E` rather than `Color.primary`, for the reason in the
        /// file header: `labelColor` is already black at 0.85, so
        /// `.primary.opacity(0.42)` renders at 0.357 — 15% short of what the
        /// design draws, on the α that carries every group label in the app.
        ///
        /// In use: `.7` (a running task's tool line) · `.65` · `.6` · `.55` ·
        /// `.5` · `.45` · **`.42` (every group label)** · `.4` · `.35` · `.32`
        /// (a resting row action) · `.3` · `.28` · `.25`.
        static func ink(_ alpha: Double) -> Color { inkBase.opacity(alpha) }

        // MARK: Surfaces

        /// Surfaces the mockup fills with, beyond `card` and `canvas`.
        static let insetSurface = Color(red: 0.980, green: 0.980, blue: 0.973)  // #FAFAF8
        static let recessed = Color(red: 0.969, green: 0.969, blue: 0.961)      // #F7F7F5
        static let footerBar = Color(red: 0.945, green: 0.945, blue: 0.937)     // #F1F1EF
        static let segmentTrack = Color(red: 0.929, green: 0.929, blue: 0.918)  // #EDEDEA
        /// `#F0F0EE` — 设置's segmented-control track, which sits on a white
        /// card and so is drawn lighter than `segmentTrack`, which sits on a
        /// sheet. Two tracks, two values; the handoff really does draw both.
        static let controlTrack = Color(red: 0.941, green: 0.941, blue: 0.933)

        /// `rgba(255,255,255,α)` — the borders and fills that exist only on the
        /// voice surface's blurred panels, where a black line disappears.
        enum OnPanel {
            /// The panel's own edge.
            static let border = Color.white.opacity(0.45)
            /// A lifted block inside it, at the three weights §04 draws.
            static let fill = Color.white.opacity(0.50)
            static let fillStrong = Color.white.opacity(0.60)
            static let fillStrongest = Color.white.opacity(0.70)
            /// A caption on the dark backdrop behind the panels.
            static let caption = Color.white.opacity(0.45)
        }

        /// The Q&A type tag's text. Darker than `accent` so it stays legible on
        /// its own 11%-accent fill.
        static let askTag = Color(red: 0.039, green: 0.361, blue: 0.784)        // #0A5CC8

        /// Unconfirmed memory, side-effecting tools, connection risk.
        static let warning = Color(red: 0.910, green: 0.592, blue: 0.227)
        static let warningText = Color(red: 0.698, green: 0.416, blue: 0.086)
        static let warningFill = Color(red: 0.910, green: 0.592, blue: 0.227).opacity(0.14)
        /// Real errors only.
        static let error = Color(red: 0.851, green: 0.282, blue: 0.231)
        /// A 5pt status dot, never a text colour.
        static let ok = Color(red: 0.204, green: 0.659, blue: 0.325)
    }

    // MARK: - Depth

    /// CSS blur maps to a SwiftUI shadow radius at half its value — `0 1px 2px`
    /// is `radius: 1, y: 1`.
    enum Shadow {
        /// `0 1px 2px rgba(0,0,0,.04)` — a card.
        static func card(_ view: some View) -> some View {
            view.shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        }
        /// `0 1px 1.5px rgba(0,0,0,.05)` — a lifted small control: icon
        /// buttons, header fields, the selected segment.
        static func control(_ view: some View) -> some View {
            view.shadow(color: .black.opacity(0.05), radius: 0.75, x: 0, y: 1)
        }
        /// `0 1px 1.5px rgba(0,0,0,.04)` — a text field, which the handoff sits
        /// one shade flatter than a button.
        static func field(_ view: some View) -> some View {
            view.shadow(color: .black.opacity(0.04), radius: 0.75, x: 0, y: 1)
        }
        /// `0 1px 2px rgba(0,0,0,.1)` — a harder lift, for a selected segment
        /// that has to read as raised off its own track.
        static func lifted(_ view: some View) -> some View {
            view.shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 1)
        }
        /// `0 1px 2px rgba(0,0,0,.25)` — a toggle's knob.
        static func knob(_ view: some View) -> some View {
            view.shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
        }
        /// `0 1px 2px rgba(13,115,250,.3)` — an accent-filled button. The
        /// coloured lift is what stops a saturated 26pt square reading as a
        /// sticker pasted on the header.
        static func accentControl(_ view: some View) -> some View {
            view.shadow(color: DS.Colour.accent.opacity(0.30), radius: 1, x: 0, y: 1)
        }
        /// `0 2px 8px rgba(13,115,250,.1)` — a running card, which also takes
        /// an accent border.
        static func running(_ view: some View) -> some View {
            view.shadow(color: DS.Colour.accent.opacity(0.10), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Metrics

    /// Fixed widths from the handoff. Measured, not eyeballed — the README's
    /// verification step checks these with screenshots.
    enum Size {
        static let sidebar: CGFloat = 212
        /// The sidebar collapsed to icons in the narrow layout.
        static let iconRail: CGFloat = 52
        static let list: CGFloat = 334
        /// Below this the window uses the narrow layout.
        static let narrowBreakpoint: CGFloat = 720
        /// Raised from 420: three columns do not fit in less.
        static let windowMinWidth: CGFloat = 460
        /// The title-bar-height strip every column starts with.
        static let headerHeight: CGFloat = 52
        /// A header control: search field, dropdown, icon button, small button.
        static let headerControl: CGFloat = 26
        /// A text field or a segmented control inside a sheet.
        static let field: CGFloat = 28
        static let statusDot: CGFloat = 5
    }

    enum Space {
        static let rowV: CGFloat = 11
        /// 会话's row gutter.
        static let rowH: CGFloat = 13
        /// Every other screen's card-row gutter. The handoff really does use
        /// two: 会话's rows are `11 13`, and 听写 / 记忆 / 设置 / MCP's are
        /// `13 14` or `12 14`.
        static let rowHWide: CGFloat = 14
        static let content: CGFloat = 16
        static let pageWide: CGFloat = 24
        static let pageNarrow: CGFloat = 14
        static let group: CGFloat = 16
        /// Between a group label and the card it labels.
        static let label: CGFloat = 8
        /// A group label's own inset, so it hangs 4pt inside the card's edge
        /// rather than flush with it.
        static let labelInset: CGFloat = 4
    }
}

extension View {
    /// A card: white, 14pt corners, hairline border, the card shadow.
    func dsCard() -> some View {
        DS.Shadow.card(
            background(DS.Colour.card, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.Colour.border, lineWidth: 0.75)
                )
        )
    }

    /// A divider between rows in a card.
    ///
    /// Takes its colour because the mockup uses two: `.06` inside list cards,
    /// `.07` for the overlay's and the sheets' separators. Defaulted to `.06`
    /// so the many call sites that are already right stay untouched, and the
    /// ones that are not name what they need.
    func dsHairline(_ edge: Edge = .top, color: Color = DS.Colour.hairline) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle()
                .fill(color)
                .frame(height: 0.75)
        }
    }
}
