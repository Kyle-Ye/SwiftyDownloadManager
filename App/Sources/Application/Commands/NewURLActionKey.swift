import SwiftUI

struct NewURLActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newURLAction: (() -> Void)? {
        get { self[NewURLActionKey.self] }
        set { self[NewURLActionKey.self] = newValue }
    }
}
