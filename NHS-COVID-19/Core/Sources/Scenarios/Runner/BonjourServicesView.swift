import SwiftUI
import BonjourServices
import Logging

struct BonjourServicesView: View {
    @State private var isEnabled: Bool

    let remoteLoggerClient: RemoteLoggerClient

    init(remoteLoggerClient: RemoteLoggerClient) {
        self.remoteLoggerClient = remoteLoggerClient
        self._isEnabled = State(initialValue: remoteLoggerClient.isEnabled)
    }

    var body: some View {
        VStack {
            Toggle(isOn: $isEnabled) {
                HStack {
                    Image(systemName: "network")
                    Text("Remote Logging")
                }
            }
            .onChange(of: isEnabled) { newValue in
                if newValue {
                    remoteLoggerClient.enable()
                } else {
                    remoteLoggerClient.disable()
                }
            }

            if isEnabled {
                DeviceBrowserView(remoteLoggerClient: remoteLoggerClient)
            }
        }
    }
}
