import Testing
@testable import QueenBeeDesign

@Suite struct TouchScalesTests {
    @Test func theCanvasKeepsTheMacsCardSizes() {
        // The iPad and iPhone canvas is drawn in these, at the desk size, so a card matches the Mac's.
        #expect(TextRole.headline.desk == 13 && TextRole.headline.weight == .semibold)
        #expect(TextRole.captionLabel.desk == 12 && TextRole.captionLabel.weight == .medium)
        #expect(TextRole.figure.desk == 11 && TextRole.figure.weight == .medium)
        #expect(TextRole.mono.desk == 12)
    }

    @Test func theTouchRolesKeepTheSizesTheDeviceAppUsed() {
        #expect(TextRole.footnote.touch == 12 && TextRole.footnoteLabel.touch == 12)
        #expect(TextRole.heading.touch == 17 && TextRole.monoHeading.touch == 17 && TextRole.monoHeading.isMono)
        #expect(TextRole.display.touch == 28)
        #expect(TextRole.body.touch == 15 && TextRole.label.touch == 15 && TextRole.caption.touch == 13)
    }

    @Test func aFingerSizedRowIsAtLeastTheTouchTarget() {
        #expect(DS.Size.touchTarget == 44)
        #expect(DS.Size.rowCompact < DS.Size.touchTarget && DS.Size.rowTall > DS.Size.touchTarget)
    }

    @Test func theWidthsRunFromNarrowestToWidest() {
        let widths = [DS.Size.menuNarrowWidth, DS.Size.noteWidth, DS.Size.calloutWidth, DS.Size.bannerWidth,
                      DS.Size.messageWidth, DS.Size.plateWidth, DS.Size.onboardingWidth, DS.Size.sheetWidth]
        #expect(widths == widths.sorted())
    }
}
