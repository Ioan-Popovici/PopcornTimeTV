//
//  HideableView.swift
//  HideableView
//
//  Created by Alexandru Tudose on 05.10.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI

struct HideableView<Content: View>: NSViewRepresentable {
    
    @Binding var isHidden: Bool
    var view: Content
    
    func makeNSView(context: Context) -> ViewContainer<Content> {
        return ViewContainer(isContentHidden: isHidden, child: view)
    }
    
    func updateNSView(_ container: ViewContainer<Content>, context: Context) {
        container.child.rootView = view
        container.isContentHidden = isHidden
    }
    
    class ViewContainer<HostedContent: View>: NSView {
        var child: NSHostingController<HostedContent>
        var didShow = false
        var isContentHidden: Bool {
            didSet {
                addOrRemove()
            }
        }

        init(isContentHidden: Bool, child: HostedContent) {
            self.child = NSHostingController(rootView: child)
            self.isContentHidden = isContentHidden
            super.init(frame: .zero)
            addOrRemove()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            child.view.frame = bounds
        }
        
        func addOrRemove() {
            if isContentHidden && child.view.superview != nil {
                child.view.removeFromSuperview()
            }
            if !isContentHidden && child.view.superview == nil {
                if !didShow {
                    DispatchQueue.main.async {
                        if !self.isContentHidden {
                            self.addSubview(self.child.view)
                            self.didShow = true
                        }
                    }
                } else {
                    addSubview(child.view)
                }
            }
        }
        
    }
}


extension View {
    func hide(_ hide: Bool) -> some View {
        HideableView(isHidden: .constant(hide), view: self)
    }
    
    func hide(_ isHidden: Binding<Bool>) -> some View {
        HideableView(isHidden: isHidden, view: self)
    }
}
