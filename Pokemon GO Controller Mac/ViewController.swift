//
//  ViewController.swift
//  Pokemon GO Controller Mac
//
//  Created by BumMo Koo on 2016. 7. 26..
//  Copyright © 2016년 BumMo Koo. All rights reserved.
//

import Cocoa
import MapKit

class ViewController: NSViewController {
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var coordinateVisualEffectView: NSVisualEffectView!
    @IBOutlet weak var coordinateTextField: NSTextField!
    
    fileprivate var preference = PreferenceManager.defaultManager
    
    var speed: Speed = Speed.walk {
        didSet {
            preference.speed = speed
            updateSpeedPopUpButton()
        }
    }
    
    var userLocation: CLLocationCoordinate2D? {
        didSet {
            preference.userLocation = userLocation
            updateUserLocationPin()
            updateCoordinateTextField()
        }
    }
    
    var favorites: [Favorite]? {
        didSet {
            preference.favorites = favorites
            updateFavoritesPins()
        }
    }
    
    fileprivate var userLocationPin: MKPointAnnotation?
    fileprivate var favoritesPins = [MKPointAnnotation]()
    
    fileprivate var rightMouseDownEvent: NSEvent?
    
    fileprivate var navigator: Navigator?

    // MARK: View
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        mapView.showsScale = true
        mapView.showsUserLocation = true
        coordinateVisualEffectView.layer?.cornerRadius = 9.0
        speed = preference.speed
        userLocation = preference.userLocation
        favorites = preference.favorites
        handleKeyPress()
        
        // Move map
        if let userLocation = userLocation {
            let latitudeDelta = UnitConverter.latitudeDegrees(fromMeter: 1000)
            let longitudeDelta = UnitConverter.longitudeDegress(fromMeter: 1000, latitude: userLocation.latitude)
            let span = MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
            let region = MKCoordinateRegion(center: userLocation, span: span)
            mapView.setRegion(region, animated: true)
        }
    }
    
    fileprivate func updateSpeedPopUpButton() {
        let windowController = view.window?.windowController as? WindowController
        windowController?.updateSpeedPopUpButton()
    }
    
    fileprivate func updateCoordinateTextField() {
        if let latitude = userLocation?.latitude, let longitude = userLocation?.longitude {
            coordinateTextField.stringValue = "\(latitude), \(longitude)"
        }
    }
    
    fileprivate func updateUserLocationPin() {
        guard let userLocation = userLocation else { return }
        if userLocationPin == nil {
            userLocationPin = MKPointAnnotation()
            mapView.addAnnotation(userLocationPin!)
        }
        userLocationPin?.coordinate = userLocation
    }
    
    fileprivate func updateFavoritesPins() {
        mapView.removeAnnotations(favoritesPins)
        guard let favorites = favorites else { return }
        for favorite in favorites {
            let annotation = MKPointAnnotation()
            annotation.coordinate = favorite.coordinate
            annotation.title = favorite.name
            mapView.addAnnotation(annotation)
            favoritesPins.append(annotation)
        }
    }
    
    // MARK: Action
    @objc fileprivate func handleAddFavoritesMenu(_ sender: NSMenuItem) {
        guard let point = rightMouseDownEvent?.locationInWindow else { return }
        let coordinate = mapView.convert(point, toCoordinateFrom: view)
        favorites?.append(Favorite(coordinate: coordinate))
        rightMouseDownEvent = nil
    }
    
    fileprivate func handleKeyPress() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] (event) -> NSEvent? in
            guard let coordinate = self?.userLocation else { return event }
            let speed = self?.speed.value ?? Speed.walk.value
            // let jitter = 0 // self?.speed.jitter ?? Speed.Walk.jitter
            let latitudeDelta = UnitConverter.latitudeDegrees(fromMeter: speed)
            let longitudeDelta = UnitConverter.longitudeDegress(fromMeter: speed, latitude: coordinate.latitude)
            let randomJitter = 0.0 // Double(arc4random_uniform(UInt32(jitter))) - 2
            let latitudeJitter = UnitConverter.latitudeDegrees(fromMeter: randomJitter)
            let longitudeJitter = UnitConverter.longitudeDegress(fromMeter: randomJitter, latitude: coordinate.latitude)
            switch event.keyCode {
            case 126: // Up
                self?.userLocation = CLLocationCoordinate2D(latitude: coordinate.latitude + latitudeDelta, longitude: coordinate.longitude + longitudeJitter)
            case 125: // Down
                self?.userLocation = CLLocationCoordinate2D(latitude: coordinate.latitude - latitudeDelta, longitude: coordinate.longitude + longitudeJitter)
            case 123: // Left
                self?.userLocation = CLLocationCoordinate2D(latitude: coordinate.latitude + latitudeJitter, longitude: coordinate.longitude - longitudeDelta)
            case 124: // Right
                self?.userLocation = CLLocationCoordinate2D(latitude: coordinate.latitude + latitudeJitter, longitude: coordinate.longitude + longitudeDelta)
            default: break
            }
            return nil
        }
    }
}

extension ViewController {
    override func mouseDown(with theEvent: NSEvent) {
        mapView.removeOverlays(mapView.overlays)
        let point = theEvent.locationInWindow
        let coordinate = mapView.convert(point, toCoordinateFrom: view)
        userLocation = coordinate
    }
    
    override func rightMouseDown(with theEvent: NSEvent) {
        rightMouseDownEvent = theEvent
        let menu = NSMenu(title: "Menu")
        menu.insertItem(withTitle: "Add to bookmark", action: #selector(handleAddFavoritesMenu(_:)), keyEquivalent: "", at: 0)
        menu.insertItem(NSMenuItem.separator(), at: 1)
        menu.insertItem(withTitle: "Walk to this location", action: #selector(handleMenu(_:)), keyEquivalent: "", at: 2)
        menu.insertItem(withTitle: "Run to this location", action: #selector(handleMenu(_:)), keyEquivalent: "", at: 3)
        menu.insertItem(withTitle: "Cycle to this location", action: #selector(handleMenu(_:)), keyEquivalent: "", at: 4)
        menu.insertItem(withTitle: "Drive to this location", action: #selector(handleMenu(_:)), keyEquivalent: "", at: 5)
        menu.insertItem(withTitle: "Race to this location", action: #selector(handleMenu(_:)), keyEquivalent: "", at: 6)
        NSMenu.popUpContextMenu(menu, with: theEvent, for: mapView)
    }
    
    func handleMenu(_ sender: NSMenuItem) {
        guard let index = sender.menu?.index(of: sender) , index >= 2 && index < 7 else { return }
        guard let speed = Speed(rawValue: index - 2) else { return }
        self.speed = speed
        
        guard let userLocation = userLocation else { return }
        guard let point = rightMouseDownEvent?.locationInWindow else { return }
        let coordinate = mapView.convert(point, toCoordinateFrom: view)
        rightMouseDownEvent = nil
        
        let transportType: MKDirectionsTransportType = speed.rawValue >= Speed.drive.rawValue ? .automobile : .walking
        navigator = Navigator(sourceCoordinate: userLocation, destinationCoordinate: coordinate, transportType: transportType)
        navigator?.findRoute({ [weak self] (route) in
            if let overlays = self?.mapView.overlays {
                self?.mapView.removeOverlays(overlays)
            }
            guard let route = route else { return }
            self?.mapView.add(route.polyline, level: .aboveRoads)
            self?.navigator?.startNavigation(speed: speed, progress: { (coordinate) in
                self?.userLocation = coordinate
            })
        })
    }
}

extension ViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.lineCap = .round
            renderer.lineWidth = 3
            renderer.strokeColor = NSColor.blue
            return renderer
        }
        return MKOverlayRenderer()
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        guard let window = view.window else { return }
        guard let favorite = favorites?.filter({ $0.coordinate == annotation.coordinate }).first else { return }
        guard let index = favorites?.index(of: favorite) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Confirm deleting this pin?"
        alert.addButton(withTitle: "Confirm")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window, completionHandler: { [weak self] (response) in
            switch response {
            case NSAlertFirstButtonReturn:
                self?.favorites?.remove(at: index)
            default: break
            }
        }) 
    }
}
