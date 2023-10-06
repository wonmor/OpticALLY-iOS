import Combine
import RealityKit
import SwiftUI
import UIKit

final class Workerman: Entity {
    var model: Entity?
    
    static var loadAsync: AnyPublisher<Workerman, Error> {
        return Entity.loadAsync(named: "workerman")
            .map { loadedWorkerman -> Workerman in
                let workerman = Workerman()
                loadedWorkerman.name = "Workerman"
                workerman.model = loadedWorkerman
                return workerman
            }
            .eraseToAnyPublisher()
    }
}

class HomeViewController: UIViewController {
    private let resourceLoader = ResourceLoader()
    
    var sceneEventsUpdateSubscription: Cancellable!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let arView = ARView(frame: view.frame,
                            cameraMode: .nonAR,
                            automaticallyConfigureSession: false)
        view.addSubview(arView)
        
        let skyboxName = "house"
        let skyboxResource = try! EnvironmentResource.load(named: skyboxName)
        arView.environment.lighting.resource = skyboxResource
        arView.environment.background = .skybox(skyboxResource)
        
        let scale: Float = 5.0 // Adjust the scale factor as needed

        let person = (try? Entity.load(named: "workerman"))!
        person.scale = SIMD3<Float>(repeating: scale)
        
        let personAnchor = AnchorEntity(world: .zero)
        personAnchor.addChild(person)
        arView.scene.anchors.append(personAnchor)
        
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 120
        
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        
        arView.scene.addAnchor(cameraAnchor)
        
        let cameraDistance: Float = 3
        var currentCameraRotation: Float = 0
        let cameraRotationSpeed: Float = 0.005
        
        sceneEventsUpdateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { _ in
            let x = sin(currentCameraRotation) * cameraDistance
            let z = cos(currentCameraRotation) * cameraDistance
            
            let cameraTranslation = SIMD3<Float>(x, 0, z)
            let cameraTransform = Transform(scale: .one,
                                            rotation: simd_quatf(),
                                            translation: cameraTranslation)
            
            camera.transform = cameraTransform
            camera.look(at: .zero, from: cameraTranslation, relativeTo: nil)
            
            currentCameraRotation += cameraRotationSpeed
        }
    }
}

