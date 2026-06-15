import AppKit
import CoreLocation
import MapKit
import SwiftUI

/// A MapKit map that lets the user click to drop route waypoints, renders the
/// route polyline, and shows a live marker at the simulated position.
struct MapView: NSViewRepresentable {
    var waypoints: [Waypoint]
    var currentCoordinate: CLLocationCoordinate2D?
    var controller: MapController
    /// Called with the map coordinate the user clicked.
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsZoomControls = true
        map.showsCompass = true
        map.showsPitchControl = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        // Single-click drops a waypoint; require exactly one click so it doesn't
        // swallow the map's own double-click-to-zoom or drag-to-pan.
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        click.numberOfClicksRequired = 1
        click.delaysPrimaryMouseButtonEvents = false
        map.addGestureRecognizer(click)
        context.coordinator.mapView = map
        context.coordinator.bindController()
        // Default region: roughly continental view until the user picks a spot.
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.03),
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            ),
            animated: false
        )
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(waypoints: waypoints, current: currentCoordinate)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        weak var mapView: MKMapView?
        private var routeOverlay: MKPolyline?
        private let currentAnnotation = MKPointAnnotation()
        private var hasCurrent = false

        init(_ parent: MapView) {
            self.parent = parent
            currentAnnotation.title = "Simulated position"
        }

        /// Expose map commands to SwiftUI through the shared MapController.
        func bindController() {
            let controller = parent.controller
            controller.recenter = { [weak self] coord, meters in
                guard let map = self?.mapView else { return }
                map.setRegion(
                    MKCoordinateRegion(center: coord, latitudinalMeters: meters, longitudinalMeters: meters),
                    animated: true
                )
            }
            controller.zoomBy = { [weak self] factor in
                guard let map = self?.mapView else { return }
                var region = map.region
                region.span = MKCoordinateSpan(
                    latitudeDelta: min(120, max(0.0008, region.span.latitudeDelta * factor)),
                    longitudeDelta: min(120, max(0.0008, region.span.longitudeDelta * factor))
                )
                map.setRegion(region, animated: true)
            }
            controller.currentCenter = { [weak self] in self?.mapView?.region.center }
        }

        @objc func handleClick(_ gr: NSClickGestureRecognizer) {
            guard let map = mapView else { return }
            let point = gr.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            parent.onTap(coord)
        }

        func sync(waypoints: [Waypoint], current: CLLocationCoordinate2D?) {
            guard let map = mapView else { return }

            // Waypoint pins: rebuild only the numbered waypoint annotations.
            let existing = map.annotations.compactMap { $0 as? WaypointAnnotation }
            map.removeAnnotations(existing)
            for (i, wp) in waypoints.enumerated() {
                let a = WaypointAnnotation()
                a.coordinate = wp.coordinate
                a.title = "\(i + 1)"
                map.addAnnotation(a)
            }

            // Route polyline.
            if let old = routeOverlay { map.removeOverlay(old) }
            if waypoints.count >= 2 {
                let line = MKPolyline(coordinates: waypoints.map(\.coordinate), count: waypoints.count)
                map.addOverlay(line)
                routeOverlay = line
            } else {
                routeOverlay = nil
            }

            // Live simulated-position marker.
            if let current {
                currentAnnotation.coordinate = current
                if !hasCurrent {
                    map.addAnnotation(currentAnnotation)
                    hasCurrent = true
                }
            } else if hasCurrent {
                map.removeAnnotation(currentAnnotation)
                hasCurrent = false
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 4
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation === currentAnnotation {
                let id = "current"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.markerTintColor = .systemGreen
                v.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
                v.displayPriority = .required
                return v
            }
            if annotation is WaypointAnnotation {
                let id = "wp"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.markerTintColor = .systemBlue
                v.glyphText = (annotation as? WaypointAnnotation)?.title ?? ""
                return v
            }
            return nil
        }
    }
}

/// Distinguishes user-placed waypoints from the live position marker.
final class WaypointAnnotation: MKPointAnnotation {}
