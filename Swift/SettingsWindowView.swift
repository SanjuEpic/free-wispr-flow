import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        SettingsTabView(settings: settings)
            .frame(width: 520)
    }
}
