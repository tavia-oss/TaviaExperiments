import PlaceImage
import PlaceVideo
import SwiftUI

public struct AppView: View {
    public init() {}

    public var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink("Place Image Center") {
                        PlaceImageView(placeMode: .screenCenter)
                    }
                    .padding(.vertical)
                    NavigationLink("Place Video Center") {
                        PlaceVideoView()
                    }
                    .padding(.vertical)
                }
            }
        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
    }
}
