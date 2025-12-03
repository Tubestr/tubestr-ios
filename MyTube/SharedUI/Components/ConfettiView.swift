//
//  ConfettiView.swift
//  MyTube
//
//  Created for EditorUXImprovements - Export Celebration
//

import SwiftUI

/// A celebratory confetti animation that plays when export completes.
/// Uses Canvas for efficient rendering of many particles.
struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var animationTimer: Timer?

    let colors: [Color] = [.orange, .pink, .yellow, .purple, .mint, Color(red: 1.0, green: 0.72, blue: 0.42), Color(red: 0.90, green: 0.69, blue: 0.73)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.position.x - 5 * particle.scale,
                        y: particle.position.y - 5 * particle.scale,
                        width: 10 * particle.scale,
                        height: 10 * particle.scale
                    )

                    var contextCopy = context
                    contextCopy.rotate(by: .degrees(particle.rotation))

                    // Draw different shapes for variety
                    switch particle.shape {
                    case 0:
                        // Square
                        contextCopy.fill(
                            Rectangle().path(in: rect),
                            with: .color(particle.color)
                        )
                    case 1:
                        // Circle
                        contextCopy.fill(
                            Circle().path(in: rect),
                            with: .color(particle.color)
                        )
                    default:
                        // Rounded rectangle
                        contextCopy.fill(
                            RoundedRectangle(cornerRadius: 2).path(in: rect),
                            with: .color(particle.color)
                        )
                    }
                }
            }
        }
        .onAppear {
            generateParticles()
            startAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func generateParticles() {
        particles = (0..<60).map { _ in
            ConfettiParticle(
                position: CGPoint(
                    x: CGFloat.random(in: 50...350),
                    y: CGFloat.random(in: -50...(-10))
                ),
                color: colors.randomElement()!,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.6...1.4),
                velocity: CGPoint(
                    x: CGFloat.random(in: -3...3),
                    y: CGFloat.random(in: 4...8)
                ),
                rotationSpeed: Double.random(in: -10...10),
                shape: Int.random(in: 0...2)
            )
        }
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            var allOffScreen = true

            for i in particles.indices {
                particles[i].position.x += particles[i].velocity.x
                particles[i].position.y += particles[i].velocity.y
                particles[i].rotation += particles[i].rotationSpeed

                // Add some wobble
                particles[i].velocity.x += CGFloat.random(in: -0.1...0.1)

                // Gravity effect
                particles[i].velocity.y += 0.15

                // Check if still on screen
                if particles[i].position.y < 500 {
                    allOffScreen = false
                }
            }

            // Stop animation when all particles have fallen
            if allOffScreen {
                timer.invalidate()
            }
        }
    }
}

/// A single confetti particle with physics properties
private struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var color: Color
    var rotation: Double
    var scale: CGFloat
    var velocity: CGPoint
    var rotationSpeed: Double
    var shape: Int
}

#Preview {
    ZStack {
        Color.black.opacity(0.6)
        ConfettiView()
            .frame(width: 400, height: 500)
    }
}

