import Foundation

enum PathSafetyPolicy {
    static func isStrictDescendant(_ candidate: URL, of root: URL) -> Bool {
        guard candidate.isFileURL, root.isFileURL else {
            return false
        }

        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents

        guard candidateComponents.count > rootComponents.count else {
            return false
        }
        return candidateComponents.prefix(rootComponents.count)
            .elementsEqual(rootComponents)
    }

    static func isExactRoot(_ candidate: URL, _ root: URL) -> Bool {
        guard candidate.isFileURL, root.isFileURL else {
            return false
        }
        return candidate.standardizedFileURL.pathComponents
            == root.standardizedFileURL.pathComponents
    }
}
