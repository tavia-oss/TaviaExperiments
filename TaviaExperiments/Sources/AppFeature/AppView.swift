import DetectCropAndPlaceAlphanumeric
import PlaceGif
import PlaceImage
import PlaceObject
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
                    NavigationLink("Place Object Center") {
                        PlaceObjectView()
                    }
                    .padding(.vertical)
                    NavigationLink("Place Gif Center") {
                        PlaceGifView()
                    }
                    .padding(.vertical)
                    NavigationLink("Place Image At Tapped") {
                        PlaceImageView(placeMode: .tappedLocation)
                    }
                    .padding(.vertical)
                    NavigationLink("Detect, Crop And Place Alphanumeric") {
                        DetectCropAndPlaceAlphanumeric.ContentView()
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
