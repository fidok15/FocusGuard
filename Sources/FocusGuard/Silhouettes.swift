import SwiftUI

/// Outlines of the clickable objects, traced on the art in its 2000x1116 coordinate space.
/// Timer, mug and sticky notes sit in the same place in all four scenes; the cat differs per scene.
enum Silhouette {
    private static func pts(_ v: [CGFloat]) -> [CGPoint] { stride(from: 0, to: v.count, by: 2).map { CGPoint(x: v[$0], y: v[$0 + 1]) } }

    static let timer = pts([379, 661, 397, 654, 495, 645, 509, 646, 527, 657, 534, 668, 538, 779, 535, 788, 523, 798, 515, 804,
                            508, 801, 431, 808, 430, 811, 423, 816, 415, 813, 414, 809, 397, 799, 383, 785, 378, 730, 379, 673])
    static let mug = pts([1393, 693, 1457, 677, 1518, 687, 1521, 715, 1536, 718, 1547, 739, 1550, 763, 1543, 792, 1527, 807, 1521, 808,
                          1518, 823, 1501, 832, 1470, 839, 1430, 835, 1400, 823, 1393, 812, 1392, 728])
    static let pinkNote = pts([1474, 868, 1599, 861, 1621, 884, 1587, 930, 1521, 935])
    static let greenNote = pts([1556, 888, 1680, 883, 1742, 942, 1605, 951])

    static let catMorning = pts([818, 475, 866, 469, 928, 455, 965, 432, 972, 446, 992, 444, 1043, 428, 1089, 426, 1135, 437, 1181, 460,
                                 1202, 497, 1213, 529, 1211, 561, 1197, 586, 1158, 598, 1089, 602, 1020, 600, 974, 598, 928, 598, 893, 598,
                                 870, 591, 847, 584, 844, 570, 859, 566, 845, 549, 842, 529, 844, 515])
    static let catDay = pts([1720, 552, 1759, 551, 1768, 549, 1792, 534, 1826, 531, 1864, 502, 1868, 548, 1879, 523, 1930, 507, 1962, 501,
                             2000, 505, 2000, 690, 1994, 676, 1930, 678, 1890, 670, 1850, 683, 1832, 702, 1829, 734, 1823, 748, 1802, 755,
                             1791, 742, 1792, 718, 1802, 694, 1807, 676, 1770, 667, 1767, 644, 1754, 630, 1749, 593, 1743, 585, 1735, 572])
    static let catSunset = pts([1369, 276, 1372, 304, 1374, 322, 1367, 341, 1372, 365, 1387, 384, 1381, 416, 1378, 455, 1372, 486, 1362, 507,
                                1344, 509, 1327, 523, 1315, 548, 1319, 575, 1338, 595, 1377, 611, 1417, 616, 1456, 609, 1495, 607, 1524, 589,
                                1537, 562, 1543, 529, 1532, 499, 1520, 474, 1504, 435, 1489, 396, 1483, 382, 1479, 349, 1472, 334, 1470, 304,
                                1465, 271, 1456, 283, 1442, 296, 1424, 295, 1405, 297])
    static let catNight = pts([359, 758, 398, 784, 468, 800, 538, 806, 503, 849, 503, 892, 503, 919, 495, 941, 452, 960, 406, 965, 371, 965,
                               357, 981, 303, 1000, 236, 1022, 155, 1030, 101, 1016, 52, 973, 46, 919, 55, 881, 79, 838, 117, 803, 171, 773,
                               209, 764, 290, 768, 340, 772])
}

/// Closed outline through points given in art coordinates, scaled to whatever frame it is drawn in.
struct OutlineShape: Shape {
    let groups: [[CGPoint]]
    var smooth = true

    func path(in r: CGRect) -> Path {
        var p = Path()
        for g in groups where g.count > 2 {
            let q = g.map { CGPoint(x: r.minX + $0.x / 2000 * r.width, y: r.minY + $0.y / 1116 * r.height) }
            if smooth { // curve through edge midpoints, so corners round a little and the line stays continuous
                let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
                p.move(to: mid(q[q.count - 1], q[0]))
                for i in 0..<q.count { p.addQuadCurve(to: mid(q[i], q[(i + 1) % q.count]), control: q[i]) }
            } else {
                p.move(to: q[0]); q.dropFirst().forEach { p.addLine(to: $0) }
            }
            p.closeSubpath()
        }
        return p
    }
}

/// Soft warm-white outline and glow hugging a silhouette, used as the hover mark.
struct HoverGlow: View {
    let shape: OutlineShape
    let on: Bool

    var body: some View {
        ZStack {
            shape.fill(Color(red: 1, green: 0.95, blue: 0.8).opacity(0.1))
            shape.stroke(Color(red: 1, green: 0.96, blue: 0.82).opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .shadow(color: Color(red: 1, green: 0.9, blue: 0.6).opacity(0.9), radius: 5)
        }
        .opacity(on ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: on)
        .allowsHitTesting(false)
    }
}

/// `--hover timer|mug|sticky|cat` forces a hover mark, for screenshots.
let forcedHover: String? = CommandLine.arguments.firstIndex(of: "--hover").flatMap { i in CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : nil }
