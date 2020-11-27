//
//  ContentView.swift
//  Worm
//
//  Created by Vitaliy on 2020-11-19.
//

import SwiftUI
import Combine

struct ContentView: View {
    @State private var childSize: CGSize = .zero
    @State private var movingStatus = "(stopped)"
    @StateObject private var wormData: WormData = WormData()
    private var isStarted = false
    
    var body: some View {
        VStack {
            Text("Tap to pause/resume \(movingStatus)")
                .font(.footnote)
            GeometryReader { geometry in
                WormView(wormData: wormData)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SizeGetter())
        }
        // in order to update field size once screen rotated
        .onPreferenceChange(SizePreferenceKey.self) { preferences in
            self.wormData.fieldSize = preferences
        }
        // add tap gesture for entire screen
        .contentShape(Rectangle())
        .onTapGesture {
            if wormData.isStarted {
                wormData.stop()
                movingStatus = "(stopped)"
            } else {
                wormData.start()
                movingStatus = "(moving)"
            }
            wormData.isStarted = !wormData.isStarted
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - Get Size

struct SizePreferenceKey: PreferenceKey {
    typealias Value = CGSize
    static var defaultValue: Value = .zero
    
    static func reduce(value: inout Value, nextValue: () -> Value) {
        // TODO: не уверен, что просто закомментировать это правильно
        // но иначе возвращается не первое значение, а значения потомков, а там 0,0
        //value = nextValue()
    }
}

struct SizeGetter: View {
    var body: some View {
        return GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        }
    }
}

// MARK: - WormData

class WormData: ObservableObject {
    
    // worm constants
    let radius: CGFloat = 15.0                 // segment radius
    let segmentNumber = 40                     // number of segments
    private let minStepsBeforeTurn: Int = 3    // min number of steps before turn
    private let maxStepsBeforeTurn: Int = 5    // max number of steps before turn
    private let pace: TimeInterval = 0.07      // move every 'pace' seconds
    private let maxYaw: Int = 90               // макс. угол рыскания при повороте (0...180)
    private let maxStepLength: CGFloat = 10    // maximum step length
    
    // worm parameters
    @Published var positions: [CGPoint] = []
    var colors: [Color] = []
    private var stepsLeft = 0
    private var azimuth: Int = 315     // текущее значение азимута в градусах
    private var xOffset: CGFloat = 0
    private var yOffset: CGFloat = 0
    
    // to generate recurring events
    private var cancellable: Cancellable?
    
    // helper for pause/resume button
    var isStarted = false
    
    // field parameters
    @Published var fieldSize: CGSize = .zero
    private var minX: CGFloat {
        return radius + 1
    }
    private var maxX: CGFloat {
        return fieldSize.width - radius - 1
    }
    private var minY: CGFloat {
        return radius + 1
    }
    private var maxY: CGFloat {
        return fieldSize.height - radius - 1
    }

    init() {
        let colorValue = 1.0 / Double(segmentNumber)
        for i in 0..<segmentNumber {
            let coordinate = radius - maxStepLength * CGFloat(i)
            positions.append(CGPoint(x: coordinate, y: coordinate))
            colors.append(Color.init(red: Double(i) * colorValue,
                                     green: Double(i) * colorValue,
                                     blue: Double(i) * colorValue))
        }
    }
    
    func start() {
        cancellable = Timer.publish(every: pace,
                                    tolerance: pace / 2,
                                    on: .main,
                                    in: .default)
            .autoconnect()
            .sink(receiveValue: { _ in
                self.move()
            })
    }
    
    func stop() {
        cancellable?.cancel()
    }
    
    private func move() {
        // if worm is out of visible area (f.e. after screen rotation)
        if !insideField(point: positions[0]) {
            // move to screen center ASAP
            let xCenter = fieldSize.width / 2
            let yCenter = fieldSize.height / 2
            xOffset = signum(a: xCenter, b: positions[0].x) * maxStepLength
            yOffset = signum(a: yCenter, b: positions[0].y) * maxStepLength
            
            let newX = positions[0].x + xOffset
            let newY = positions[0].y + yOffset
            positions.remove(at: segmentNumber - 1)
            positions.insert(CGPoint(x: newX, y: newY), at: 0)
            return
        }
        
        // if leg is over - generate new leg parameters
        if stepsLeft == 0 {
            stepsLeft = Int.random(in: minStepsBeforeTurn...maxStepsBeforeTurn)
            (xOffset, yOffset) = newOffsets()
        }
        stepsLeft -= 1
        
        var newX = positions[0].x + xOffset
        var newY = positions[0].y + yOffset
        
        // if the new position is out of visible area
        if newX < minX || newX > maxX {
            newX = newX - 2 * xOffset
            flipForX()
        }
        if newY < minY || newY > maxY {
            newY = newY - 2 * yOffset
            flipForY()
        }
        
        positions.remove(at: segmentNumber - 1)
        positions.insert(CGPoint(x: newX, y: newY), at: 0)
    }
    
    // calculate new xOffset and yOffset based on random(yaw and stepLenth)
    private func newOffsets() -> (CGFloat, CGFloat) {
        azimuth = azimuth + Int.random(in: -maxYaw...maxYaw)
        // для дебага приведу azimuth к диапазону 0...359
        azimuth = azimuth % 360  // если больше 360
        azimuth = azimuth < 0 ? 360 + azimuth : azimuth // если меньше 0
        let azimuthRadian = CGFloat(Double(azimuth) * .pi / 180.0)

        let xOffset = maxStepLength * cos(azimuthRadian)
        let yOffset = maxStepLength * sin(azimuthRadian)
        return (xOffset, yOffset)
    }
    
    // when worm crosses x border - flip x direction
    private func flipForX() {
        xOffset = -xOffset
        azimuth = (azimuth <= 180 ? 180 : 540) - azimuth
    }
    
    // when worm crosses y border - flip y direction
    private func flipForY() {
        yOffset = -yOffset
        azimuth = 360 - azimuth
    }
    
    // checks if 'point' is inside visible area
    private func insideField(point: CGPoint) -> Bool {
        if point.x < minX || point.x > maxX { return false }
        if point.y < minY || point.y > maxY { return false }
        return true
    }
    
    // signum function for CGFloat
    private func signum(a: CGFloat, b: CGFloat) -> CGFloat {
        if a > b { return CGFloat(1) }
        if a < b { return CGFloat(-1) }
        return CGFloat(0)
    }
    
}

// MARK: - WormView

struct WormView: View {
    @ObservedObject var wormData: WormData
    
    var body: some View {
        // need to reverse in order to print from the tail to the head
        // that makes overlapping colors look better
        ForEach((0..<(wormData.segmentNumber)).reversed(), id: \.self) { i in
            SegmentView(segmentCenter: wormData.positions[i],
                        radius: wormData.radius,
                        color: wormData.colors[i])
        }
    }
}

// MARK: - SegmentView

struct SegmentView: View {
    var segmentCenter: CGPoint
    var radius: CGFloat
    var color: Color
    
    var body: some View {
        SegmentShape(center: segmentCenter, radius: radius)
            .fill(color)
    }
    
    struct SegmentShape: Shape {
        var center: CGPoint
        var radius: CGFloat
        
        func path(in rect: CGRect) -> Path {
            var path = Path()

            path.move(to: CGPoint(x: center.x + radius, y: center.y))
            path.addArc(center: center,
                        radius: radius,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360),
                        clockwise: false)
            
            //return path.strokedPath(.init(lineWidth: 2, dash: [6, 2], dashPhase: 10))
            return path.strokedPath(.init(lineWidth: 2))
            //return path
        }
    }
}

// TODO: это действительно так работает???
extension CGPoint: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}
