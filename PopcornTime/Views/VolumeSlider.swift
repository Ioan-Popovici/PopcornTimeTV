//
//  VolumeSlider.swift
//  VolumeSlider
//
//  Created by Alexandru Tudose on 14.08.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import MediaPlayer
import UIKit

struct VolumeButtonSlider: View {
    @State var volume: Float = 0
    @State var mute = false
    var onVolumeChange: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            VolumeSlider(volume: $volume, mute: $mute)
                .padding(.top, 14)
                .padding(.trailing, 10)

            Button {
                mute.toggle()
            } label: {
                Color.clear
                    .overlay {
                        Image(volume > 0 ? "Volume Maximum" : "Volume Minimum")
                            .padding(.leading, maskValue)
                            .mask(Rectangle()
                                    .padding(.trailing, maskValue))
                    }
                .clipped()
            }
            .frame(width: 41)
        }
        .onChange(of: volume) {
            onVolumeChange()
        }
    }

    var maskValue: CGFloat {
        switch volume {
        case 0:
            return 0
        case 0..<0.4:
            return 12
        case 0.4..<0.7:
            return 6.5
        default:
            return 0
        }
    }
}


struct VolumeSlider: UIViewRepresentable {
    @Binding var volume: Float
    @Binding var mute: Bool
    @State private var volumeObservation: NSKeyValueObservation?
    @State private var slider: UISlider?
    
    private static var previousValue: Float = -1
    
    
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        if let slider = volumeView.subviews.compactMap({$0 as? UISlider}).first {
            context.coordinator.addObservers(slider: slider)
            DispatchQueue.main.async {
                mute = slider.value == 0
                volume = slider.value
                self.slider = slider
            }
        }
        return volumeView
    }
    
    func updateUIView(_ view: MPVolumeView, context: Context) {
        guard let slider = slider else {
            return
        }

        if mute && slider.value > 0 {
            VolumeSlider.previousValue = slider.value
            slider.value = 0
            DispatchQueue.main.async {
                volume = 0
            }
        } else if !mute && slider.value == 0 {
            let value = VolumeSlider.previousValue != -1 ? VolumeSlider.previousValue : 0.3
            slider.value = value
            DispatchQueue.main.async {
                volume = value
            }
            VolumeSlider.previousValue = -1
        }
    }
    
    func makeCoordinator() -> VolumeSliderCoordinator {
        return VolumeSliderCoordinator(volume: $volume, mute: $mute)
    }
    
    @MainActor
    class VolumeSliderCoordinator {
        var volume: Binding<Float>
        var mute: Binding<Bool>
        
        init(volume: Binding<Float>, mute: Binding<Bool>) {
            self.volume = volume
            self.mute = mute
        }
        
        func addObservers(slider: UISlider) {
            slider.addTarget(self, action: #selector(volumeChanged(slider:)), for: .valueChanged)
        }
        
        @objc func volumeChanged(slider: UISlider) {
            volume.wrappedValue = slider.value
            mute.wrappedValue = slider.value == 0
        }
    }
}

struct VolumeSlider_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VolumeButtonSlider(volume: 0)
            VolumeButtonSlider(volume: 0.3)
            VolumeButtonSlider(volume: 0.50)
            VolumeButtonSlider(volume: 1)
        }
            .frame(width: 200, height: 41)
            .preferredColorScheme(.dark)
            .previewLayout(.fixed(width: 300, height: 60))
    }
}


