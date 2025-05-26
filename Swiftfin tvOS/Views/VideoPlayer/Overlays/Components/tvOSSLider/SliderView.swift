//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct tvOSSliderView: UIViewRepresentable {

    @Binding
    private var value: CGFloat

    private var onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UITVOSSlider {
        let slider = UITVOSSlider(
            value: _value,
            onEditingChanged: onEditingChanged
        )

        slider.value = Float(value)
        slider.minimumValue = 0
        slider.maximumValue = 1.0 // Match progress range 0-1
        slider.thumbSize = 25
        slider.thumbTintColor = .white
        slider.minimumTrackTintColor = .white
        slider.focusScaleFactor = 1.4
        slider.panDampingValue = 50
        slider.fineTunningVelocityThreshold = 1000

        return slider
    }

    func updateUIView(_ uiView: UITVOSSlider, context: Context) {
        // Update slider when binding value changes
        let currentValue = Float(value)
        if abs(uiView.value - currentValue) > 0.001 { // Avoid unnecessary updates
            uiView.setValue(currentValue, animated: false)
        }
    }
}

extension tvOSSliderView {

    init(value: Binding<CGFloat>) {
        self.init(
            value: value,
            onEditingChanged: { _ in }
        )
    }

    func onEditingChanged(_ action: @escaping (Bool) -> Void) -> Self {
        copy(modifying: \.onEditingChanged, with: action)
    }
}
