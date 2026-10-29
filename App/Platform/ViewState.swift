import SwiftUI

// Name the property-wrapper type explicitly: the macOS 27 SDK also exports a
// State macro whose plugin is absent from standalone Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>
