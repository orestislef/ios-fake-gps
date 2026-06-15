import CoreLocation
import Foundation
import MapKit

/// Bridge that lets SwiftUI views drive the underlying `MKMapView`
/// (recenter, zoom). The `MapView` coordinator wires these closures up.
@MainActor
final class MapController: ObservableObject {
    var recenter: ((CLLocationCoordinate2D, CLLocationDistance) -> Void)?
    var zoomBy: ((Double) -> Void)?
    var currentCenter: (() -> CLLocationCoordinate2D?)?

    func center(on coord: CLLocationCoordinate2D, meters: CLLocationDistance = 1_500) {
        recenter?(coord, meters)
    }

    func zoomIn() { zoomBy?(0.5) }
    func zoomOut() { zoomBy?(2.0) }
}

/// Address / place search backed by MapKit's local search.
@MainActor
final class PlaceSearch: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var isSearching = false

    private var task: Task<Void, Never>?

    func run(near center: CLLocationCoordinate2D?) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; return }

        task = Task { [weak self] in
            guard let self else { return }
            self.isSearching = true
            defer { self.isSearching = false }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            if let center {
                request.region = MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
                )
            }
            do {
                let response = try await MKLocalSearch(request: request).start()
                if !Task.isCancelled { self.results = response.mapItems }
            } catch {
                if !Task.isCancelled { self.results = [] }
            }
        }
    }

    func clear() {
        task?.cancel()
        query = ""
        results = []
    }
}

extension MKMapItem {
    var displayTitle: String { name ?? "Unknown" }
    var displaySubtitle: String {
        let p = placemark
        return [p.thoroughfare, p.locality, p.administrativeArea, p.country]
            .compactMap { $0 }.joined(separator: ", ")
    }
    var coordinate: CLLocationCoordinate2D { placemark.coordinate }
}
