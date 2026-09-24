import Foundation
import Testing
@testable import ShotGenieCore

@Suite struct ShellPathTests {
    @Test func escapesSpacesLikeFinderDrag() {
        let p = "/Users/ana/Pictures/ScreenCaptures/Screenshot 2026-09-23 at 7.30.54 PM.png"
        #expect(ShellPath.escaped(p) == #"/Users/ana/Pictures/ScreenCaptures/Screenshot\ 2026-09-23\ at\ 7.30.54\ PM.png"#)
    }

    @Test func escapesShellMetacharacters() {
        #expect(ShellPath.escaped("/a/b (1)&'x'.png") == #"/a/b\ \(1\)\&\'x\'.png"#)
        #expect(ShellPath.escaped("/a/$HOME;*?.png") == #"/a/\$HOME\;\*\?.png"#)
    }

    @Test func leavesPlainPathsAlone() {
        #expect(ShellPath.escaped("/tmp/foo-bar_1.png") == "/tmp/foo-bar_1.png")
    }
}

@Suite struct CaptureListingTests {
    let base = Date(timeIntervalSince1970: 1_000_000)

    func entry(_ name: String, _ offset: TimeInterval) -> CaptureListing.Entry {
        .init(url: URL(fileURLWithPath: "/x/\(name)"), created: base.addingTimeInterval(offset))
    }

    @Test func keepsNewestFiveImagesNewestFirst() {
        let entries = (0..<8).map { entry("s\($0).png", TimeInterval($0)) }
        let out = CaptureListing.latest(entries, limit: 5)
        #expect(out.map(\.url.lastPathComponent) == ["s7.png", "s6.png", "s5.png", "s4.png", "s3.png"])
    }

    @Test func ignoresHiddenTempFilesAndNonImages() {
        let entries = [
            entry(".Screenshot 2026.png", 10),   // temporal de screencapture antes del rename
            entry("Screen Recording.mov", 9),
            entry("notas.txt", 8),
            entry("ok.PNG", 1),
            entry("foto.jpg", 2),
            entry("x.heic", 3),
        ]
        let out = CaptureListing.latest(entries, limit: 5)
        #expect(out.map(\.url.lastPathComponent) == ["x.heic", "foto.jpg", "ok.PNG"])
    }
}

@Suite struct FisheyeTests {
    @Test func onlyHoveredIsBig() {
        let s = Fisheye.sizes(count: 5, hovered: 2)
        #expect(s[2] == Fisheye.big)
        #expect(s.enumerated().filter { $0.offset != 2 }.allSatisfy { $0.element == Fisheye.row })
    }

    @Test func containerHeightIsConstant() {
        // Con estilo menú el alto total no cambia al mover la lupa: el panel no salta.
        let h = Fisheye.containerHeight(count: 5)
        #expect(h == Fisheye.big.height + 4 * Fisheye.row.height + 4 * Fisheye.spacing)
        for hovered in 0..<5 {
            let total = Fisheye.sizes(count: 5, hovered: hovered).reduce(0) { $0 + $1.height } + 4 * Fisheye.spacing
            #expect(total == h)
        }
    }

    @Test func topRowIsOldestBottomIsNewest() {
        let h = Fisheye.containerHeight(count: 5)
        // y crece hacia abajo (SwiftUI). Con la más nueva ampliada (abajo):
        #expect(Fisheye.index(forY: 1, hovered: 0, count: 5) == 4)
        #expect(Fisheye.index(forY: h - 1, hovered: 0, count: 5) == 0)
        // Fuera de rango se recorta.
        #expect(Fisheye.index(forY: -50, hovered: 0, count: 5) == 4)
        #expect(Fisheye.index(forY: h + 50, hovered: 0, count: 5) == 0)
    }

    @Test func noOscillation() {
        // Si el cursor en y elige la fila i, al ampliar i el cursor sigue sobre i (punto fijo).
        let n = 5
        let h = Fisheye.containerHeight(count: n)
        for hovered in 0..<n {
            var y: CGFloat = 0
            while y < h {
                let i = Fisheye.index(forY: y, hovered: hovered, count: n)
                #expect(Fisheye.index(forY: y, hovered: i, count: n) == i, "y=\(y) desde \(hovered) → \(i)")
                y += 1
            }
        }
    }

    @Test func emptyAndSingle() {
        #expect(Fisheye.containerHeight(count: 0) == 0)
        #expect(Fisheye.containerHeight(count: 1) == Fisheye.big.height)
        #expect(Fisheye.index(forY: 10, hovered: 0, count: 1) == 0)
    }
}

@Suite struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let size = CGSize(width: 340, height: 660)

    @Test func centersOnCursorAboveVisibleDock() {
        let visible = CGRect(x: 0, y: 80, width: 1512, height: 870) // Dock visible de 80 pt
        let o = PanelPlacement.origin(mouse: CGPoint(x: 700, y: 30), panel: size, screen: screen, visible: visible)
        #expect(o.x == CGFloat(530))
        #expect(o.y >= 80)          // no tapa el Dock
    }

    @Test func autohiddenDockUsesCursorHeight() {
        let visible = CGRect(x: 0, y: 4, width: 1512, height: 946) // Dock oculto
        let o = PanelPlacement.origin(mouse: CGPoint(x: 700, y: 40), panel: size, screen: screen, visible: visible)
        #expect(o.y >= 40 + 60)     // por encima del icono (aunque esté ampliado)
    }

    @Test func clampsToScreenEdges() {
        let visible = CGRect(x: 0, y: 80, width: 1512, height: 870)
        let left = PanelPlacement.origin(mouse: CGPoint(x: 20, y: 30), panel: size, screen: screen, visible: visible)
        #expect(left.x == PanelPlacement.margin)
        let right = PanelPlacement.origin(mouse: CGPoint(x: 1500, y: 30), panel: size, screen: screen, visible: visible)
        #expect(right.x == 1512 - 340 - PanelPlacement.margin)
        let top = PanelPlacement.origin(mouse: CGPoint(x: 700, y: 900), panel: size, screen: screen, visible: visible)
        #expect(top.y + size.height <= visible.maxY)
    }
}

@Suite struct RelativeTimeTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func largestUnitThatFits() {
        #expect(RelativeTime.ago(now.addingTimeInterval(-12), now: now)! == (12, .seconds))
        #expect(RelativeTime.ago(now.addingTimeInterval(-200), now: now)! == (3, .minutes))
        #expect(RelativeTime.ago(now.addingTimeInterval(-3_700), now: now)! == (1, .hours))
        #expect(RelativeTime.ago(now.addingTimeInterval(-200_000), now: now)! == (2, .days))
        #expect(RelativeTime.ago(now.addingTimeInterval(5), now: now) == nil)
    }
}

@Suite struct FanLayoutTests {
    @Test func bottomRowIsStraightAndHigherRowsCurveRight() {
        let p = (0..<6).map { FanLayout.placement(row: $0) }
        #expect(p[0].dx == 0)
        #expect(p[0].degrees == 0)
        for k in 1..<6 {
            #expect(p[k].dx > p[k - 1].dx)            // se abre hacia la derecha al subir
            #expect(p[k].degrees > p[k - 1].degrees)  // y se inclina cada vez más
            #expect(p[k].rise == CGFloat(k) * FanLayout.step)
        }
        #expect(p[5].degrees < 25)                   // abanico suave, como el del Dock
    }

    @Test func hoverPicksNearestRowAndIgnoresFolderRow() {
        let count = 5                                  // 5 capturas + la fila «abrir carpeta» arriba
        let h = FanLayout.height(rows: count + 1)
        for k in 0..<count {
            let y = FanLayout.centerY(row: k, height: h)
            #expect(FanLayout.index(forY: y, height: h, count: count) == k)
            #expect(FanLayout.index(forY: y + FanLayout.step * 0.4, height: h, count: count) == k)
        }
        // La fila de la carpeta (k = count) no se amplía.
        #expect(FanLayout.index(forY: FanLayout.centerY(row: count, height: h), height: h, count: count) == nil)
        // Por debajo de la fila 0 sigue siendo la 0 (el cursor viene del Dock).
        #expect(FanLayout.index(forY: h - 1, height: h, count: count) == 0)
    }

    @Test func enlargedThumbnailFitsVertically() {
        // La miniatura ampliada de la fila de abajo no se corta con el borde de la ventana.
        let grown = FanLayout.thumb.height * FanLayout.defaultMagnification
        #expect(FanLayout.overflow() >= (grown - FanLayout.thumb.height) / 2)
    }

    @Test func panelIsWideEnoughForCurveAndMagnification() {
        let rows = 6
        let top = FanLayout.placement(row: rows - 1)
        let needed = FanLayout.padding + FanLayout.labelWidth + FanLayout.gap
            + FanLayout.thumb.width * FanLayout.defaultMagnification + top.dx
        #expect(FanLayout.width(rows: rows) >= needed)
    }
}

@Suite struct MagnificationSettingTests {
    @Test func clampsToRange() {
        #expect(FanLayout.clampMagnification(0.2) == FanLayout.magnificationRange.lowerBound)
        #expect(FanLayout.clampMagnification(99) == FanLayout.magnificationRange.upperBound)
        #expect(FanLayout.clampMagnification(.nan) == FanLayout.defaultMagnification)
        #expect(FanLayout.clampMagnification(3) == CGFloat(3))
    }

    @Test func everyValueInRangeFitsAndHoverStillWorks() {
        for m in stride(from: FanLayout.magnificationRange.lowerBound, through: FanLayout.magnificationRange.upperBound, by: 0.1) {
            let rows = 6
            let h = FanLayout.height(rows: rows, magnification: m)
            // La ampliada no se corta ni por arriba ni por abajo…
            #expect(FanLayout.overflow(magnification: m) >= FanLayout.thumb.height * (m - 1) / 2)
            // …ni por la derecha, aunque esté en lo alto del arco.
            let top = FanLayout.placement(row: rows - 2)
            #expect(FanLayout.width(rows: rows, magnification: m)
                    >= FanLayout.padding + FanLayout.labelWidth + FanLayout.gap + FanLayout.thumb.width * m + top.dx)
            // Cada fila sigue eligiéndose a sí misma bajo el cursor.
            for k in 0..<(rows - 1) {
                let y = FanLayout.centerY(row: k, height: h, magnification: m)
                #expect(FanLayout.index(forY: y, height: h, count: rows - 1, magnification: m) == k)
            }
        }
    }
}

@Suite struct AnchoredPlacementTests {
    @Test func thumbnailColumnSitsOverTheDockIcon() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 80, width: 1512, height: 870)
        let size = CGSize(width: 600, height: 500)
        let o = PanelPlacement.origin(mouse: CGPoint(x: 900, y: 30), panel: size, anchorX: 450, screen: screen, visible: visible)
        #expect(o.x == CGFloat(450))                 // 900 - 450: la columna de miniaturas cae sobre el icono
    }
}

@Suite struct GenieTests {
    let rect = CGRect(x: 400, y: 200, width: 600, height: 400)   // y hacia abajo
    let target = CGPoint(x: 900, y: 1000)                        // el icono, abajo

    @Test func startsAsTheUndistortedImage() {
        let s = Genie.strip(v0: 0.5, v1: 0.6, rect: rect, target: target, curve: 0, slide: 0)!
        #expect(abs(s.dest.minX - 400) < 0.001 && abs(s.dest.width - 600) < 0.001)
        #expect(abs(s.dest.minY - 400) < 0.001 && abs(s.dest.height - 40) < 0.001)
        #expect(s.image == rect)
    }

    @Test func curveNarrowsTowardTheIconOnly() {
        // Con la curva completa, la parte alta conserva el ancho y la que toca el icono se estrecha.
        let top = Genie.strip(v0: 0, v1: 0.01, rect: rect, target: target, curve: 1, slide: 0)!
        let bottom = Genie.strip(v0: 0.99, v1: 1, rect: rect, target: target, curve: 1, slide: 0)!
        #expect(top.dest.width > 590)
        #expect(bottom.dest.width < top.dest.width)
        #expect(bottom.dest.midX > top.dest.midX)                 // se inclina hacia el icono (a la derecha)
    }

    @Test func slideSwallowsRowsIntoTheIcon() {
        let half = (0..<100).compactMap { i in
            Genie.strip(v0: CGFloat(i) / 100, v1: CGFloat(i + 1) / 100, rect: rect, target: target, curve: 1, slide: 0.75)
        }
        // A 3/4 del recorrido (600 de 800 pt) la mitad inferior ya pasó el icono.
        #expect(half.count > 40 && half.count < 60)
        #expect(half.allSatisfy { $0.dest.maxY <= target.y + 0.001 })
        let done = (0..<100).compactMap { i in
            Genie.strip(v0: CGFloat(i) / 100, v1: CGFloat(i + 1) / 100, rect: rect, target: target, curve: 1, slide: 1)
        }
        #expect(done.isEmpty)
    }

    @Test func nearTheIconTheWidthIsTheIconWidth() {
        let s = (0..<400).compactMap { i in
            Genie.strip(v0: CGFloat(i) / 400, v1: CGFloat(i + 1) / 400, rect: rect, target: target, curve: 1, slide: 0.6)
        }.last!
        #expect(s.dest.width < Genie.targetWidth * 1.6)
    }

    @Test func phasesCoverTheTimeline() {
        let a = Genie.phases(0)
        #expect(a.appear == 0 && a.curve == 0 && a.slide == 0)
        let z = Genie.phases(1)
        #expect(z.appear == 1 && z.curve == 1 && z.slide == 1)
        var last = Genie.phases(0)
        for i in 1...100 {
            let p = Genie.phases(Double(i) / 100)
            #expect(p.appear >= last.appear && p.curve >= last.curve && p.slide >= last.slide)
            last = p
        }
    }

    @Test func startRectFitsAndKeepsAspect() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let r = Genie.startRect(imagePoints: CGSize(width: 3000, height: 1000), in: screen)
        #expect(r.width <= screen.width * Genie.maxScreenFraction + 0.001)
        #expect(abs(r.width / r.height - 3) < 0.01)
        let small = Genie.startRect(imagePoints: CGSize(width: 200, height: 100), in: screen)
        #expect(small.width == 200)                                // no se amplía por encima de su tamaño
        #expect(abs(small.midX - screen.midX) < 0.001)
    }
}

@Suite struct DockGeometryTests {
    // Las tres pantallas de Ender, en coordenadas de Accesibilidad (origen arriba a la izquierda de la principal).
    let screens = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),         // principal
        CGRect(x: 1158, y: 1080, width: 1512, height: 982),    // portátil, justo debajo
        CGRect(x: 1920, y: -357, width: 1920, height: 1080),   // la de la derecha
    ]

    @Test func hiddenDockOnMainScreenIsNotMistakenForTheLaptopBelow() {
        let item = CGRect(x: 1598, y: 1080, width: 34.7, height: 50)   // medido: Dock oculto en la principal
        #expect(DockGeometry.screenIndex(item: item, screens: screens) == 0)
    }

    @Test func hiddenDockOnLaptop() {
        let item = CGRect(x: 2417.4, y: 2062, width: 34.7, height: 50)  // medido: Dock oculto en el portátil
        #expect(DockGeometry.screenIndex(item: item, screens: screens) == 1)
    }

    @Test func visibleDockOnLaptop() {
        let item = CGRect(x: 2417.4, y: 2010, width: 34.7, height: 50)
        #expect(DockGeometry.screenIndex(item: item, screens: screens) == 1)
    }

    @Test func noScreenUnderTheIcon() {
        let item = CGRect(x: 9000, y: 1080, width: 34.7, height: 50)
        #expect(DockGeometry.screenIndex(item: item, screens: screens) == nil)
    }
}

@Suite struct GenieSafetyTests {
    @Test func targetInsideTheImageFallsBackToTheBottomEdge() {
        let screen = CGSize(width: 1512, height: 982)
        let rect = Genie.startRect(imagePoints: CGSize(width: 800, height: 500), in: CGRect(origin: .zero, size: screen))
        let fixed = Genie.safeTarget(CGPoint(x: rect.midX, y: rect.midY), rect: rect, screen: screen)
        #expect(fixed.y > rect.maxY)
        // Un icono por encima de la imagen ya no se «corrige»: el genio sube hacia él.
        let above = CGPoint(x: 400, y: 4)
        #expect(Genie.safeTarget(above, rect: rect, screen: screen) == above)
    }
}

@Suite struct GenieDirectionTests {
    let canvas = CGSize(width: 1512, height: 982)
    var rect: CGRect { Genie.startRect(imagePoints: CGSize(width: 800, height: 500), in: CGRect(origin: .zero, size: canvas)) }

    @Test func picksTheSideWhereTheIconIs() {
        #expect(Genie.direction(rect: rect, target: CGPoint(x: 457, y: 978)) == .down)
        #expect(Genie.direction(rect: rect, target: CGPoint(x: 457, y: 4)) == .up)      // Dock en la pantalla de arriba
        #expect(Genie.direction(rect: rect, target: CGPoint(x: 1508, y: 500)) == .right)
        #expect(Genie.direction(rect: rect, target: CGPoint(x: 4, y: 500)) == .left)
    }

    @Test func undistortedImageIsUprightInEveryDirection() {
        // Sin curva ni caída, la franja que cubre toda la imagen debe verse igual que la imagen: ni girada ni en espejo.
        let targets: [Genie.Direction: CGPoint] = [
            .down: CGPoint(x: 457, y: 978), .up: CGPoint(x: 457, y: 4),
            .right: CGPoint(x: 1508, y: 500), .left: CGPoint(x: 4, y: 500),
        ]
        for (dir, target) in targets {
            let space = Genie.genieSpace(rect: rect, target: target, canvas: canvas, direction: dir)
            let strip = Genie.strip(v0: 0, v1: 1, rect: space.rect, target: space.target, curve: 0, slide: 0)!
            let (draw, local) = Genie.imageTransform(direction: dir, into: strip.image)
            let toScreen = local.concatenating(Genie.screenTransform(dir, canvas: canvas))
            let topLeft = CGPoint(x: draw.minX, y: draw.minY).applying(toScreen)
            let bottomRight = CGPoint(x: draw.maxX, y: draw.maxY).applying(toScreen)
            #expect(abs(topLeft.x - rect.minX) < 0.01 && abs(topLeft.y - rect.minY) < 0.01, "\(dir) esquina sup. izq.")
            #expect(abs(bottomRight.x - rect.maxX) < 0.01 && abs(bottomRight.y - rect.maxY) < 0.01, "\(dir) esquina inf. der.")
        }
    }

    @Test func genieSpaceAlwaysHasTheTargetBelow() {
        for (dir, target) in [(Genie.Direction.up, CGPoint(x: 457, y: 4)), (.right, CGPoint(x: 1508, y: 500)), (.left, CGPoint(x: 4, y: 500))] {
            let space = Genie.genieSpace(rect: rect, target: target, canvas: canvas, direction: dir)
            #expect(space.target.y > space.rect.maxY, "\(dir)")
        }
    }

    @Test func iconOnAnotherScreenBecomesTheNearestEdgeOfThisOne() {
        // Captura en el portátil (debajo de la pantalla principal); el Dock está abajo en la principal, justo encima.
        let laptop = CGRect(x: 1158, y: -982, width: 1512, height: 982)   // AppKit
        let icon = CGPoint(x: 1615, y: 4)   // lo que da target(): icono en el borde inferior de la pantalla principal
        let p = Genie.pointOnScreen(icon, screen: laptop)
        #expect(p.x == CGFloat(1615))
        #expect(p.y > laptop.maxY - 10 && p.y <= laptop.maxY)             // borde superior del portátil
    }
}

@Suite struct FanPlacementTests {
    // Pantalla del portátil de la prueba real (coordenadas de AppKit).
    let screen = CGRect(x: 1158, y: -982, width: 1512, height: 982)
    let rows = 6

    @Test func thumbnailsCenteredOnTheIconAndBottomRowJustAboveIt() {
        let icon = CGPoint(x: 1600, y: -920)   // centro x, borde superior
        let p = FanPlacement.place(iconTop: icon, rows: rows, magnification: 4.2, screen: screen, visible: screen)
        #expect(p.magnification == 4.2)
        #expect(p.origin.x + FanLayout.anchorX == icon.x)   // la miniatura de abajo, centrada en el icono
        #expect(abs(p.origin.y + FanLayout.overflow(magnification: 4.2) - (icon.y + FanPlacement.gap)) < 0.001)
    }

    @Test func nearTheRightEdgeTheMagnifierShrinksInsteadOfMovingTheFan() {
        let icon = CGPoint(x: 2425, y: -920)   // la prueba real: icono a 245 pt del borde derecho
        let p = FanPlacement.place(iconTop: icon, rows: rows, magnification: 5.9, screen: screen, visible: screen)
        #expect(p.magnification < 5.9)
        #expect(p.origin.x + FanLayout.anchorX == icon.x)
        #expect(p.origin.x + FanLayout.width(rows: rows, magnification: p.magnification) <= screen.maxX - PanelPlacement.margin)
    }

    @Test func atTheVeryEdgeItStillFitsOnScreen() {
        let icon = CGPoint(x: screen.maxX - 5, y: -920)
        let p = FanPlacement.place(iconTop: icon, rows: rows, magnification: 5.9, screen: screen, visible: screen)
        #expect(p.magnification == FanLayout.magnificationRange.lowerBound)
        #expect(p.origin.x + FanLayout.width(rows: rows, magnification: p.magnification) <= screen.maxX - PanelPlacement.margin)
    }
}
