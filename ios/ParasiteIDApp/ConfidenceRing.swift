import SwiftUI

/// A circular arc that fills clockwise from the top.
///
/// `percent` is the number shown and is the value the outcome was decided from, so the ring
/// can never read "50%" under a label chosen from 0.496. `progress` (0.0...1.0) only drives
/// the animation.
struct ConfidenceRing: View {
    let percent: Int
    var color: Color = Color(red: 0.40, green: 0.69, blue: 0.20)
    var progress: Double = 1
    var lineWidth: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(percent)%")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Model score \(percent) percent")
    }
}

#Preview {
    ConfidenceRing(percent: 87)
        .frame(width: 220, height: 220)
}
