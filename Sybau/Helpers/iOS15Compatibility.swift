import SwiftUI

// iOS 15 Compatibility Extensions

@available(iOS 15.0, *)
extension View {
    @ViewBuilder
    func conditionalToolbarItem<Content: View>(_ condition: Bool, @ViewBuilder content: () -> Content) -> some View {
        if condition {
            self.toolbar {
                content()
            }
        } else {
            self
        }
    }
}

// Fix for conditional toolbar items on iOS 15
extension View {
    @ViewBuilder
    func compatibleToolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar {
                content()
            }
        } else {
            self.toolbar(content: content)
        }
    }
}

// Extension for handling navigation bar items on iOS 15
extension View {
    @ViewBuilder
    func compatibleNavigationBarItems<Leading: View, Trailing: View>(
        leading: Leading?,
        trailing: Trailing?
    ) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar {
                if let leading = leading {
                    ToolbarItem(placement: .navigationBarLeading) {
                        leading
                    }
                }
                if let trailing = trailing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        trailing
                    }
                }
            }
        } else {
            self.navigationBarItems(leading: leading, trailing: trailing)
        }
    }
}

// Extension for handling font weight and italic on iOS 15
extension Text {
    @ViewBuilder
    func compatibleFontWeight(_ weight: Font.Weight) -> some View {
        if #available(iOS 16.0, *) {
            self.fontWeight(weight)
        } else {
            self.font(.system(size: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: weight))
        }
    }
    
    @ViewBuilder
    func compatibleItalic(_ isItalic: Bool = true) -> some View {
        if #available(iOS 16.0, *) {
            self.italic(isItalic)
        } else {
            if isItalic {
                self.font(.system(size: UIFont.preferredFont(forTextStyle: .body).pointSize).italic())
            } else {
                self
            }
        }
    }
}
