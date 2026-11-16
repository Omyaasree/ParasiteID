import SwiftUI

/// A circular arc that fills clockwise from the top. `progress` is 0.0...1.0.
struct ConfidenceRing: View {
    let progress: Double
    var lineWidth: CGFloat = 22
    var color: Color = Color(red: 0.40, green: 0.69, blue: 0.20)

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .contentTransition(.numericText(value: progress))
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent chance of nits")
    }
}

#Preview {
    ConfidenceRing(progress: 0.87)
        .frame(width: 220, height: 220)
}
