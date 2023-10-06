import Foundation
import Combine
import RealityKit

class ResourceLoader {
    typealias LoadCompletion = (Result<Workerman, Error>) -> Void
    
    private var loadCancellable: AnyCancellable?
    private var workerman: Workerman?
    
    func createPerson() throws -> Entity {
        guard let person = workerman?.model else {
            throw ResourceLoaderError.resourceNotLoaded
        }
        return person.clone(recursive: true)
    }
    
    enum ResourceLoaderError: Error {
        case resourceNotLoaded
    }
    
    func loadResources(completion: @escaping LoadCompletion) -> AnyCancellable? {
        guard let workerman else {
            loadCancellable = Workerman.loadAsync.sink { result in
                if case let .failure(error) = result {
                    print("Failed to load Workerman: \(error)")
                    completion(.failure(error))
                }
            } receiveValue: { [weak self] workerman in
                guard let self else {
                    return
                }
                self.workerman = workerman
                completion(.success(workerman))
            }
            return loadCancellable
        }
        completion(.success(workerman))
        return loadCancellable
    }
}

enum ResourceLoaderError: Error {
    case resourceNotLoaded
}
